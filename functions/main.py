# Welcome to Cloud Functions for Firebase for Python!
# To get started, simply uncomment the below code or create your own.
# Deploy with `firebase deploy`

from firebase_functions import https_fn
from firebase_functions.options import set_global_options
from firebase_admin import initialize_app, firestore
import firebase_admin
from typing import List, Dict, Any
import datetime

# For cost control, you can set the maximum number of containers that can be
# running at the same time. This helps mitigate the impact of unexpected
# traffic spikes by instead downgrading performance. This limit is a per-function
# limit. You can override the limit for each function using the max_instances
# parameter in the decorator, e.g. @https_fn.on_request(max_instances=5).
set_global_options(max_instances=10)

app = None

def _init_app():
    global app
    if app is None:
        app = initialize_app()
    return app

def _db():
    _init_app()
    return firestore.client()

def _date_str(dt: datetime.date) -> str:
    return dt.strftime('%Y-%m-%d')

def _safe_num(v, default=0.0) -> float:
    try:
        return float(v)
    except Exception:
        return float(default)

def _calc_sma(series: List[float], period: int) -> float:
    if len(series) < period or period <= 0:
        return series[-1] if series else 0.0
    return sum(series[-period:]) / period

def _calc_rsi(prices: List[float], period: int = 14) -> float:
    if len(prices) < period + 1:
        return 50.0
    gains: List[float] = []
    losses: List[float] = []
    for i in range(1, len(prices)):
        ch = prices[i] - prices[i-1]
        gains.append(ch if ch > 0 else 0.0)
        losses.append(-ch if ch < 0 else 0.0)
    if len(gains) < period:
        return 50.0
    avg_gain = sum(gains[:period]) / period
    avg_loss = sum(losses[:period]) / period
    for i in range(period, len(gains)):
        avg_gain = (avg_gain * (period - 1) + gains[i]) / period
        avg_loss = (avg_loss * (period - 1) + losses[i]) / period
    if avg_loss == 0:
        return 100.0
    rs = avg_gain / avg_loss
    return 100 - (100 / (1 + rs))

@https_fn.on_call(region="asia-northeast3")
def ensure_chart_and_analyze(req: https_fn.CallableRequest) -> Dict[str, Any]:
    """간단한 Python Functions: 100일 캔들 보장 + 기본 지표 계산 후 저장.
    클라이언트/다른 Functions 완성 전까지 임시 백엔드 역할.
    body: { uid, symbol }
    저장: users/{uid}/analysis/{symbol}
    캔들: charts/{symbol}/daily/{yyyy-MM-dd}
    """
    data = req.data or {}
    uid: str = data.get('uid') or ''
    symbol: str = data.get('symbol') or ''
    if not uid or not symbol:
        return {'ok': False, 'error': 'uid,symbol required'}

    db = _db()
    # 100일 캔들 로드
    today = datetime.date.today()
    start = today - datetime.timedelta(days=150)
    daily_ref = db.collection('charts').document(symbol).collection('daily')
    docs = daily_ref.where('date', '>=', _date_str(start)).order_by('date').stream()
    candles: List[Dict[str, Any]] = []
    for d in docs:
        candles.append(d.to_dict())
    candles = sorted(candles, key=lambda x: x.get('date',''))
    if len(candles) < 1:
        # 완전 무자료
        return {'ok': False, 'error': 'no_chart'}

    closes = [_safe_num(c.get('close')) for c in candles]
    highs = [_safe_num(c.get('high')) for c in candles]
    lows = [_safe_num(c.get('low')) for c in candles]
    volumes = [int(c.get('volume') or 0) for c in candles]

    # 지표 계산(간이)
    rsi = _calc_rsi(closes)
    ma5 = _calc_sma(closes, 5)
    ma20 = _calc_sma(closes, 20)
    avg_vol = sum(volumes[-20:]) / max(1, min(20, len(volumes)))
    cur_vol = volumes[-1] if volumes else 0

    # 점수 간이 스케일링
    def score_from_rsi(v: float) -> float:
        if v >= 70: return -0.2
        if v <= 30: return 0.2
        return ((v - 50.0) / 50.0) * 0.2

    def score_from_ma(price: float, ma: float) -> float:
        if ma <= 0: return 0.0
        diff = (price - ma) / ma
        return max(-0.2, min(0.2, diff))

    def score_from_volume(cur: float, avgv: float) -> float:
        if avgv <= 0: return 0.0
        ratio = cur / avgv
        return max(-0.2, min(0.2, (ratio - 1.0)))

    current_price = closes[-1] if closes else 0.0
    scores = {
        'rsi': score_from_rsi(rsi),
        'movingAverage': (score_from_ma(current_price, ma5) * 0.5) + (score_from_ma(current_price, ma20) * 0.5),
        'macd': 0.0, # 간이 버전: 추후 강화
        'bollinger': 0.0,
        'vwap': 0.0,
        'adx': 0.0,
        'volume': score_from_volume(cur_vol, avg_vol),
    }
    weights = {
        'volume': 0.20,
        'rsi': 0.20,
        'macd': 0.20,
        'bollinger': 0.15,
        'movingAverage': 0.15,
        'vwap': 0.05,
        'adx': 0.05,
    }
    comprehensive = sum((scores[k] * w) for k, w in weights.items())

    analysis_doc = {
        'symbol': symbol,
        'timestamp': int(datetime.datetime.utcnow().timestamp() * 1000),
        'currentPrice': current_price,
        'technicalData': {
            'rsi': rsi,
            'ma5': ma5,
            'ma20': ma20,
            'ma60': _calc_sma(closes, 60),
            'currentVolume': cur_vol,
            'avgVolume': avg_vol,
            'open': _safe_num(candles[-1].get('open')),
            'high': _safe_num(candles[-1].get('high')),
            'low': _safe_num(candles[-1].get('low')),
        },
        'individualScores': scores,
        'analysis': {
            'rsi': {'score': scores['rsi'], 'weight': weights['rsi']},
            'movingAverage': {'score': scores['movingAverage'], 'weight': weights['movingAverage']},
            'volume': {'score': scores['volume'], 'weight': weights['volume']},
            'macd': {'score': 0.0, 'weight': weights['macd']},
            'bollinger': {'score': 0.0, 'weight': weights['bollinger']},
            'vwap': {'score': 0.0, 'weight': weights['vwap']},
            'adx': {'score': 0.0, 'weight': weights['adx']},
        },
        'comprehensiveScore': comprehensive,
        'signalStrength': '중립',
        'tradingDecision': 'HOLD',
    }

    db.collection('users').document(uid).collection('analysis').document(symbol).set(analysis_doc)
    # 가격 캐시 저장(prices/{symbol}) (차트가 60개 미만이어도 최소 필드 기록)
    price_doc = {
        'symbol': symbol,
        'currentPrice': current_price,
        'prevClose': closes[-2] if len(closes) >= 2 else current_price,
        'open': _safe_num(candles[-1].get('open')),
        'high': _safe_num(candles[-1].get('high')),
        'low': _safe_num(candles[-1].get('low')),
        'volume': cur_vol,
        'timestamp': int(datetime.datetime.utcnow().timestamp() * 1000),
    }
    db.collection('prices').document(symbol).set(price_doc, merge=True)
    return {'ok': True, 'comprehensiveScore': comprehensive}


@https_fn.on_call(region="asia-northeast3")
def getDailyChart(req: https_fn.CallableRequest) -> Dict[str, Any]:
    """charts/{symbol}/daily에서 최근 N개 일봉을 반환.
    입력: { symbol, days=100 }
    반환: { items: [ {date, open, high, low, close, volume} ] }
    """
    data = req.data or {}
    symbol: str = (data.get('symbol') or '').strip()
    days: int = int(data.get('days') or 100)
    if not symbol:
        return {'items': []}
    if days <= 0:
        days = 100
    db = _db()
    # 최근 days개 역순으로 가져오기
    docs = db.collection('charts').document(symbol).collection('daily').order_by('date', direction=firestore.Query.DESCENDING).limit(days).stream()
    items: List[Dict[str, Any]] = []
    for d in docs:
        c = d.to_dict() or {}
        items.append({
            'date': c.get('date') or d.id,
            'open': _safe_num(c.get('open')),
            'high': _safe_num(c.get('high')),
            'low': _safe_num(c.get('low')),
            'close': _safe_num(c.get('close')),
            'volume': int(c.get('volume') or 0),
        })
    items = list(reversed(items))  # 오래된→최신 순으로 정렬
    return {'items': items}


@https_fn.on_call(region="asia-northeast3")
def getCurrentPrice(req: https_fn.CallableRequest) -> Dict[str, Any]:
    """charts/{symbol}/daily에서 최신 데이터를 현재가로 변환하여 반환.
    입력: { symbol }
    반환: { hasData: bool, data: {...} }
    """
    data = req.data or {}
    symbol: str = (data.get('symbol') or '').strip()
    if not symbol:
        return {'hasData': False}
    
    db = _db()
    
    # 1) prices/{symbol} 우선 확인
    snap = db.collection('prices').document(symbol).get()
    doc = snap.to_dict() or {}
    if snap.exists and doc.get('currentPrice'):
        # 표준 키로 정규화
        normalized = {
            'symbol': symbol,
            'currentPrice': _safe_num(doc.get('currentPrice') or doc.get('prpr') or doc.get('close')),
            'prevClose': _safe_num(doc.get('prevClose') or doc.get('yesterdayClose') or 0),
            'open': _safe_num(doc.get('open') or 0),
            'high': _safe_num(doc.get('high') or 0),
            'low': _safe_num(doc.get('low') or 0),
            'volume': int(doc.get('volume') or 0),
            'timestamp': int(doc.get('timestamp') or 0),
        }
        return {'hasData': True, 'data': normalized}
    
    # 2) charts/{symbol}/daily에서 최신 데이터를 현재가로 변환
    try:
        daily_ref = db.collection('charts').document(symbol).collection('daily')
        docs = list(daily_ref.order_by('date_ts', direction=firestore.Query.DESCENDING).limit(2).stream())
        
        if len(docs) >= 1:
            latest = docs[0].to_dict() or {}
            prev_close = latest.get('close')
            
            # 전일 데이터가 있으면 사용, 없으면 최신 데이터 사용
            if len(docs) >= 2:
                prev_day = docs[1].to_dict() or {}
                prev_close = prev_day.get('close') or prev_close
            
            if latest.get('close'):
                # 차트 데이터를 현재가 데이터로 변환
                current_price_data = {
                    'symbol': symbol,
                    'currentPrice': _safe_num(latest.get('close')),
                    'prevClose': _safe_num(prev_close),
                    'open': _safe_num(latest.get('open') or 0),
                    'high': _safe_num(latest.get('high') or 0),
                    'low': _safe_num(latest.get('low') or 0),
                    'volume': int(latest.get('volume') or 0),
                    'timestamp': int(latest.get('date_ts') or 0),
                }
                return {'hasData': True, 'data': current_price_data}
    except Exception as e:
        print(f'❌ 차트 데이터에서 현재가 변환 실패: {symbol} - {e}')
    
    # 3) fallback: 분석 문서에서 기술 데이터 활용
    uid = (req.auth.uid if hasattr(req, 'auth') and req.auth else None) or (req.data or {}).get('uid')
    if uid:
        try:
            a = db.collection('users').document(uid).collection('analysis').document(symbol).get()
            ad = a.to_dict() or {}
            td = ad.get('technicalData') or {}
            fallback = {
                'symbol': symbol,
                'currentPrice': _safe_num(ad.get('currentPrice') or td.get('currentPrice') or 0),
                'prevClose': _safe_num(ad.get('prevClose') or td.get('prevClose') or 0),
                'open': _safe_num(td.get('open') or 0),
                'high': _safe_num(td.get('high') or 0),
                'low': _safe_num(td.get('low') or 0),
                'volume': int(td.get('currentVolume') or 0),
                'timestamp': int(ad.get('timestamp') or 0),
            }
            if fallback['currentPrice'] or fallback['prevClose']:
                return {'hasData': True, 'data': fallback}
        except Exception:
            pass
    
    return {'hasData': False}


@https_fn.on_call(region="asia-northeast3")
def saveApiCredentials(req: https_fn.CallableRequest) -> Dict[str, Any]:
    """앱에서 전달받은 앱키/계좌를 서버에 저장. 민감 값은 저장하지 않고 마스킹된 메타만 기록.
    입력: { uid, appKey, appSecret, accountNo }
    저장: users/{uid}/settings/api (isConfigured, maskedAccount, updatedAt)
    실제 비밀 저장은 Secret Manager 사용 권장(여기서는 생략).
    """
    data = req.data or {}
    uid: str = (data.get('uid') or '').strip()
    app_key: str = (data.get('appKey') or '').strip()
    app_secret: str = (data.get('appSecret') or '').strip()
    account_no: str = (data.get('accountNo') or '').strip()
    missing = []
    if not uid:
        missing.append('uid')
    if not app_key:
        missing.append('appKey')
    if not app_secret:
        missing.append('appSecret')
    if not account_no:
        missing.append('accountNo')
    if missing:
        return {'ok': False, 'error': 'invalid_parameters', 'missing': missing}

    masked = account_no[:3] + '-' + ('*' * max(0, len(account_no) - 6)) + '-' + account_no[-3:]
    db = _db()
    db.collection('users').document(uid).collection('settings').document('api').set({
        'isConfigured': True,
        'maskedAccount': masked,
        'updatedAt': firestore.SERVER_TIMESTAMP,
    }, merge=True)
    # 디버그 로그 저장(선택) - 민감값 저장하지 않음
    try:
        db.collection('logs').document('api_credentials').collection('events').add({
            'uid': uid,
            'maskedAccount': masked,
            'ts': firestore.SERVER_TIMESTAMP,
        })
    except Exception:
        pass
    # NOTE: 실제 비밀 저장은 Secret Manager 사용 권장
    return {'ok': True}
#
#
# @https_fn.on_request()
# def on_request_example(req: https_fn.Request) -> https_fn.Response:
#     return https_fn.Response("Hello world!")