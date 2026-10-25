from __future__ import annotations
import argparse
import base64
import ctypes
from ctypes import wintypes
import csv
import json
import os
from datetime import datetime
from pathlib import Path
import re
import sys
from urllib.parse import urlparse

import requests

ROOT = Path(__file__).resolve().parent
AUTH_FILE = ROOT / 'techem_auth.dpapi'
OUTPUT_BASENAME = ROOT / 'techem_heating_history'
BASE_URL = 'https://mieter.techem.de'
SESSION_COOKIE = '__Secure-next-auth.session-token'

# Windows Data Protection API: auth state is encrypted for the current Windows user.
class DATA_BLOB(ctypes.Structure):
    _fields_ = [('cbData', wintypes.DWORD), ('pbData', ctypes.POINTER(ctypes.c_ubyte))]

def _blob(data: bytes):
    buf = ctypes.create_string_buffer(data, len(data))
    return DATA_BLOB(len(data), ctypes.cast(buf, ctypes.POINTER(ctypes.c_ubyte))), buf

def dpapi_protect(data: bytes) -> bytes:
    src, keepalive = _blob(data)
    dst = DATA_BLOB()
    crypt = ctypes.windll.crypt32.CryptProtectData
    crypt.argtypes = [ctypes.POINTER(DATA_BLOB), wintypes.LPCWSTR, ctypes.POINTER(DATA_BLOB), wintypes.LPVOID, wintypes.LPVOID, wintypes.DWORD, ctypes.POINTER(DATA_BLOB)]
    crypt.restype = wintypes.BOOL
    if not crypt(ctypes.byref(src), 'Techem heating exporter', None, None, None, 0x1, ctypes.byref(dst)):
        raise ctypes.WinError()
    try:
        return ctypes.string_at(dst.pbData, dst.cbData)
    finally:
        ctypes.windll.kernel32.LocalFree(dst.pbData)

def dpapi_unprotect(data: bytes) -> bytes:
    src, keepalive = _blob(data)
    dst = DATA_BLOB()
    crypt = ctypes.windll.crypt32.CryptUnprotectData
    crypt.argtypes = [ctypes.POINTER(DATA_BLOB), ctypes.POINTER(wintypes.LPWSTR), ctypes.POINTER(DATA_BLOB), wintypes.LPVOID, wintypes.LPVOID, wintypes.DWORD, ctypes.POINTER(DATA_BLOB)]
    crypt.restype = wintypes.BOOL
    if not crypt(ctypes.byref(src), None, None, None, None, 0x1, ctypes.byref(dst)):
        raise ctypes.WinError()
    try:
        return ctypes.string_at(dst.pbData, dst.cbData)
    finally:
        ctypes.windll.kernel32.LocalFree(dst.pbData)

def save_auth(auth: dict) -> None:
    encrypted = dpapi_protect(json.dumps(auth, separators=(',', ':')).encode('utf-8'))
    AUTH_FILE.write_bytes(encrypted)
    try:
        os.chmod(AUTH_FILE, 0o600)
    except OSError:
        pass

def load_auth() -> dict:
    if not AUTH_FILE.exists():
        raise RuntimeError('No encrypted Techem session yet. Run once with --bootstrap while the existing logged-in Chrome debug session is open.')
    return json.loads(dpapi_unprotect(AUTH_FILE.read_bytes()).decode('utf-8'))

async def bootstrap_from_browser() -> None:
    try:
        from pyppeteer import connect
    except ImportError as e:
        raise RuntimeError('Pyppeteer is needed only for the one-time --bootstrap step.') from e
    browser = await connect(browserURL='http://127.0.0.1:9222', defaultViewport=None)
    try:
        target = next((t for t in browser.targets() if t.type == 'page' and 'mieter.techem.de' in (t.url or '') and '/consumptions/heating/' in (t.url or '')), None)
        if target is None:
            raise RuntimeError('Open the Techem heating history in your already logged-in Chrome debug session, then retry --bootstrap.')
        page = await target.page()
        cookies = await page.cookies()
        session_cookie = next((c for c in cookies if c.get('name') == SESSION_COOKIE and 'mieter.techem.de' in c.get('domain', '')), None)
        if not session_cookie:
            raise RuntimeError('Techem session cookie was not found; the portal may have logged out.')
        parsed = urlparse(page.url)
        match = re.match(r'^(.*?/consumptions/heating/)(\d{4}-\d{2})/?$', parsed.path)
        if not match:
            raise RuntimeError('Could not identify the Techem heating page route.')
        auth = {
            'session_cookie': session_cookie['value'],
            'route_prefix': match.group(1),
            'route_period': match.group(2),
            'user_agent': await page.evaluate('navigator.userAgent'),
            'bootstrapped_at': datetime.now().astimezone().isoformat(),
        }
        save_auth(auth)
        print('Saved encrypted Techem session state for this Windows user.')
        print('The session token is DPAPI-encrypted; no cookie or tenant route was printed.')
    finally:
        await browser.disconnect()

def parse_records(html: str) -> list[dict]:
    pattern = (r'\\"period\\":\\"(\d{4}-\d{2})\\",'
               r'\\"service\\":\\"HEATING\\",\\"unitOfMeasure\\":\\"KWH\\",'
               r'\\"status\\":\\"([^\\"]+)\\",\\"amount\\":([^,]+),'
               r'\\"quality\\":([^,]+),\\"revision\\":(\d+),'
               r'\\"createdAt\\":\\"([^\\"]+)\\",'
               r'\\"mixedHeatingEquipment\\":(true|false)')
    by_period = {}
    for period, status, amount, quality, revision, created_at, mixed in re.findall(pattern, html):
        by_period[period] = {
            'period': period, 'service': 'HEATING', 'unit': 'kWh',
            'status': status, 'amount_kwh': float(amount),
            'quality': float(quality), 'revision': int(revision),
            'created_at': created_at, 'mixed_heating_equipment': mixed == 'true'
        }
    return sorted(by_period.values(), key=lambda r: r['period'])

def export() -> None:
    auth = load_auth()
    session = requests.Session()
    session.cookies.set(SESSION_COOKIE, auth['session_cookie'], domain='mieter.techem.de', path='/')
    headers = {
        'User-Agent': auth['user_agent'],
        'Accept-Language': 'en-US,en;q=0.9,de;q=0.8',
        'Cache-Control': 'no-cache', 'Pragma': 'no-cache',
        'Referer': BASE_URL + auth['route_prefix'],
        'Origin': BASE_URL,
    }
    # Validate and renew the NextAuth session before fetching private data.
    response = session.get(BASE_URL + '/api/auth/session', headers={**headers, 'Accept': 'application/json'}, timeout=30)
    if response.status_code in (401, 403) or response.status_code != 200:
        raise RuntimeError(f'Techem session validation failed (HTTP {response.status_code}). Re-run --bootstrap after signing in.')
    try:
        session_info = response.json()
    except ValueError as e:
        raise RuntimeError('Techem session endpoint did not return JSON; session may have expired.') from e
    if not session_info.get('user'):
        raise RuntimeError('Techem session has expired. Sign in and rerun --bootstrap once.')
    # Persist a refreshed session token, if NextAuth rotated it. Never print it.
    refreshed = session.cookies.get(SESSION_COOKIE)
    if refreshed and refreshed != auth['session_cookie']:
        auth['session_cookie'] = refreshed
        save_auth(auth)

    # Request the last known period route. The payload contains the complete period list
    # and monthly history, so the URL does not need to be guessed for future months.
    url = BASE_URL + auth['route_prefix'] + auth.get('route_period', '2026-09')
    page_response = session.get(url, headers={**headers, 'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'}, timeout=45)
    if page_response.status_code in (401, 403) or page_response.status_code != 200:
        raise RuntimeError(f'Techem heating page request failed (HTTP {page_response.status_code}). Session may need a fresh bootstrap.')
    html = page_response.text
    records = parse_records(html)
    if not records:
        raise RuntimeError('No monthly heating records found in Techem page data; refusing to overwrite existing exports.')
    periods = sorted(set(re.findall(r'\\"period\\":\\"(\d{4}-\d{2})\\"', html)))
    latest = max((r['period'] for r in records), default=None)
    if not latest:
        raise RuntimeError('Could not determine the latest available completed month.')
    if auth.get('route_period') != latest:
        auth['route_period'] = latest
        save_auth(auth)
    output = {
        'source': 'Techem tenant portal',
        'extraction_method': 'Python requests using a DPAPI-protected NextAuth session; Next.js server-rendered payload',
        'extracted_at': datetime.now().astimezone().isoformat(),
        'latest_available_period': latest,
        'records': records,
    }
    json_path = OUTPUT_BASENAME.with_suffix('.json')
    csv_path = OUTPUT_BASENAME.with_suffix('.csv')
    tmp_json = json_path.with_suffix('.json.tmp')
    tmp_csv = csv_path.with_suffix('.csv.tmp')
    tmp_json.write_text(json.dumps(output, ensure_ascii=False, indent=2), encoding='utf-8')
    with tmp_csv.open('w', encoding='utf-8-sig', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=list(records[0].keys()))
        writer.writeheader()
        writer.writerows(records)
    tmp_json.replace(json_path)
    tmp_csv.replace(csv_path)
    print(f'Exported {len(records)} monthly heating records: {records[0]["period"]} to {records[-1]["period"]}.')
    print(f'Latest month available in Techem: {latest} (not a real-time/current-month reading).')
    print(f'CSV: {csv_path}')
    print(f'JSON: {json_path}')

async def main_async():
    parser = argparse.ArgumentParser(description='Export monthly heating history from Techem without opening a browser on regular runs.')
    parser.add_argument('--bootstrap', action='store_true', help='One-time import of the authenticated session from existing Chrome debug browser.')
    args = parser.parse_args()
    if args.bootstrap:
        await bootstrap_from_browser()
    else:
        export()

if __name__ == '__main__':
    import asyncio
    if sys.platform != 'win32':
        raise SystemExit('This script uses Windows DPAPI for protecting the session token.')
    asyncio.run(main_async())
