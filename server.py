from flask import Flask, jsonify, request, send_from_directory
from flask_cors import CORS
import pandas as pd
import os
import numpy as np

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
app = Flask(__name__, static_folder=os.path.join(BASE_DIR, 'build', 'web'))
CORS(app)

# --- 設定：CSVファイルのパス ---
CSV_PATH = os.path.join(BASE_DIR, 'Pitching_2026_data.csv')

# 選手IDと名前の対応表
PLAYER_MAP = {
    "1000404249": "寺瀨太紀", "1000348995": "藤本竜輝", "1000311709": "漢人友也",
    "1000467177": "堀陸人", "1000311711": "川原嗣貴", "1000311712": "今仲泰一",
    "1000311689": "井村勇介", "1000396211": "岩井天斗", "1000399856": "太田悠雅",
    "1000311715": "花城凪都", "1000518386": "岩佐直哉", "1000518385": "樫本旺亮"
}

# 球種の表示順序（指定通り）
PITCH_ORDER = [
    "Fastball", "Sinker", "Curveball", "Slider", "Cutter", "Splitter", "Changeup"
]

def get_data():
    if not os.path.exists(CSV_PATH):
        return pd.DataFrame()
    
    # CSV読み込み（型エラーを防ぐため low_memory=False）
    df = pd.read_csv(CSV_PATH, encoding='utf-8-sig', low_memory=False)
    df.columns = [c.strip() for c in df.columns]

    # ID列の特定（PitcherId または 2番目の列）
    target_col = 'PitcherId' if 'PitcherId' in df.columns else (df.columns[1] if len(df.columns) > 1 else df.columns[0])
    
    # IDを抽出して名前に変換
    df['temp_id'] = df[target_col].astype(str).str.split('.').str[0].str.strip()
    df['display_name'] = df['temp_id'].map(PLAYER_MAP).str.strip()
    
    # 登録外の選手を除外
    df = df.dropna(subset=['display_name']).copy()

    # 本番データのみ（PitchSession == "Live"）
    if 'PitchSession' in df.columns:
        df = df[df['PitchSession'] == 'Live'].copy()

    # 日付と年度の処理（ゼロ埋めで統一し、文字列ソートが正しく機能するようにする）
    date_col = 'Date' if 'Date' in df.columns else df.columns[0]
    df['date_dt'] = pd.to_datetime(df[date_col], errors='coerce')
    df = df.dropna(subset=['date_dt']).copy()
    df['date_clean'] = df['date_dt'].dt.strftime('%Y/%m/%d')
    df['year_str'] = df['date_dt'].dt.year.astype(str)
    
    # 数値列のクリーニング（単位計算のため）
    metrics = ['RelSpeed', 'SpinRate', 'InducedVertBreak', 'HorzBreak', 'RelSide', 'RelHeight', 'Extension', 'EffVelocity', 'VertRelAngle', 'HorzRelAngle', 'ZoneSpeed']
    for m in metrics:
        if m in df.columns:
            df[m] = pd.to_numeric(df[m], errors='coerce')

    # 球速減衰（リリース球速 - ゾーン球速）
    if 'ZoneSpeed' in df.columns:
        df['SpeedDecay'] = df['RelSpeed'] - df['ZoneSpeed']
    else:
        df['SpeedDecay'] = np.nan


    return df

@app.route('/players', methods=['GET'])
def get_players():
    df = get_data()
    if df.empty: return jsonify([])
    return jsonify(sorted(df['display_name'].unique().tolist()))

@app.route('/years', methods=['GET'])
def get_years():
    df = get_data()
    if df.empty: return jsonify(["すべて"])
    years = sorted(df['year_str'].dropna().unique().tolist())
    return jsonify(["すべて"] + years)

@app.route('/analyze', methods=['GET'])
def analyze():
    target_name = (request.args.get('player_name') or "").strip()
    target_year = (request.args.get('year') or "すべて").strip()
    
    df = get_data()
    if df.empty: return jsonify([])

    # フィルタリング
    if target_name:
        df = df[df['display_name'] == target_name]
    if target_year != "すべて" and target_year != "":
        df = df[df['year_str'] == target_year]

    # 球種列の特定（TaggedPitchType, PitchType, pitch_type に対応）
    p_col = 'TaggedPitchType' if 'TaggedPitchType' in df.columns else \
            ('PitchType' if 'PitchType' in df.columns else 'pitch_type')
    
    metrics = ['RelSpeed', 'SpinRate', 'InducedVertBreak', 'HorzBreak', 'RelSide', 'RelHeight', 'Extension', 'EffVelocity', 'SpeedDecay']
    grouped = df.groupby(['date_clean', p_col]).agg(
        pitch_count=(p_col, 'count'),
        **{f'{m}_{s}': (m, s) for m in metrics for s in ['mean', 'max', 'min']}
    ).reset_index()

    def get_sort_score(pitch):
        return PITCH_ORDER.index(pitch) if pitch in PITCH_ORDER else len(PITCH_ORDER) + 1

    grouped['pitch_sort_idx'] = grouped[p_col].apply(get_sort_score)
    grouped = grouped.sort_values(by=['date_clean', 'pitch_sort_idx'], ascending=[False, True])

    def safe_val(val):
        try:
            v = float(val)
            return v if v == v else 0.0  # NaN チェック
        except (TypeError, ValueError):
            return 0.0

    results = []
    for _, row in grouped.iterrows():
        def m_dict(key):
            return {
                'avg': safe_val(row.get(f'{key}_mean', 0)),
                'max': safe_val(row.get(f'{key}_max', 0)),
                'min': safe_val(row.get(f'{key}_min', 0)),
            }
        results.append({
            'date': str(row['date_clean']),
            'pitch_type': str(row[p_col]),
            'count': int(row['pitch_count']),
            'metrics': {m: m_dict(m) for m in metrics}
        })
    return jsonify(results)

@app.route('/pitch_map', methods=['GET'])
def pitch_map():
    target_name = (request.args.get('player_name') or "").strip()
    target_year = (request.args.get('year') or "すべて").strip()
    df = get_data()
    if df.empty: return jsonify([])
    if target_name:
        df = df[df['display_name'] == target_name]
    if target_year != "すべて":
        df = df[df['year_str'] == target_year]
    p_col = 'TaggedPitchType' if 'TaggedPitchType' in df.columns else 'PitchType'
    sub = df[['date_clean', p_col, 'HorzBreak', 'InducedVertBreak']].dropna()
    results = []
    for _, row in sub.iterrows():
        results.append({
            'date': str(row['date_clean']),
            'pitch_type': str(row[p_col]),
            'horz': round(float(row['HorzBreak']), 2),
            'vert': round(float(row['InducedVertBreak']), 2),
        })
    return jsonify(results)

@app.route('/tilt', methods=['GET'])
def tilt():
    target_name = (request.args.get('player_name') or "").strip()
    target_year = (request.args.get('year') or "すべて").strip()
    df = get_data()
    if df.empty: return jsonify([])
    if target_name:
        df = df[df['display_name'] == target_name]
    if target_year != "すべて":
        df = df[df['year_str'] == target_year]
    p_col = 'TaggedPitchType' if 'TaggedPitchType' in df.columns else 'PitchType'
    if 'Tilt' not in df.columns:
        return jsonify([])

    def tilt_to_degrees(t):
        try:
            parts = str(t).strip().split(':')
            hours = int(parts[0]) % 12
            minutes = int(parts[1])
            return hours * 30 + minutes * 0.5
        except:
            return None

    df['tilt_deg'] = df['Tilt'].apply(tilt_to_degrees)
    sub = df[['date_clean', p_col, 'Tilt', 'tilt_deg']].dropna()
    results = []
    for _, row in sub.iterrows():
        results.append({
            'date': str(row['date_clean']),
            'pitch_type': str(row[p_col]),
            'tilt': str(row['Tilt']),
            'tilt_deg': float(row['tilt_deg']),
        })
    return jsonify(results)

@app.route('/arm_angle', methods=['GET'])
def arm_angle():
    target_name = (request.args.get('player_name') or "").strip()
    target_year = (request.args.get('year') or "すべて").strip()
    df = get_data()
    if df.empty: return jsonify([])
    if target_name:
        df = df[df['display_name'] == target_name]
    if target_year != "すべて":
        df = df[df['year_str'] == target_year]
    p_col = 'TaggedPitchType' if 'TaggedPitchType' in df.columns else 'PitchType'
    for col in ['RelSide', 'RelHeight', 'Extension']:
        if col not in df.columns:
            df[col] = float('nan')
    sub = df[['date_clean', p_col, 'RelSide', 'RelHeight', 'Extension']].dropna()
    results = []
    for _, row in sub.iterrows():
        results.append({
            'date': str(row['date_clean']),
            'pitch_type': str(row[p_col]),
            'rel_side': round(float(row['RelSide']), 2),
            'rel_height': round(float(row['RelHeight']), 2),
            'extension': round(float(row['Extension']), 2),
        })
    return jsonify(results)

@app.route('/pitches', methods=['GET'])
def pitches():
    target_name = (request.args.get('player_name') or "").strip()
    target_year = (request.args.get('year') or "すべて").strip()
    df = get_data()
    if df.empty: return jsonify([])
    if target_name:
        df = df[df['display_name'] == target_name]
    if target_year != "すべて":
        df = df[df['year_str'] == target_year]
    p_col = 'TaggedPitchType' if 'TaggedPitchType' in df.columns else 'PitchType'

    cols = ['date_clean', p_col, 'RelSpeed', 'SpinRate', 'InducedVertBreak',
            'HorzBreak', 'RelSide', 'RelHeight', 'Extension', 'EffVelocity', 'SpeedDecay']
    if 'Tilt' in df.columns:
        cols.append('Tilt')
    existing = [c for c in cols if c in df.columns]
    sub = df[existing].sort_values('date_clean', ascending=False)

    def sf(val, dec=1):
        try:
            f = float(val)
            return None if (f != f) else round(f, dec)
        except:
            return None

    results = []
    for _, row in sub.iterrows():
        results.append({
            'date': str(row['date_clean']),
            'pitch_type': str(row.get(p_col, '')),
            'speed': sf(row.get('RelSpeed')),
            'spin': sf(row.get('SpinRate'), 0),
            'vert': sf(row.get('InducedVertBreak')),
            'horz': sf(row.get('HorzBreak')),
            'rel_side': sf(row.get('RelSide'), 2),
            'rel_height': sf(row.get('RelHeight'), 2),
            'extension': sf(row.get('Extension'), 2),
            'eff_vel': sf(row.get('EffVelocity')),
            'decay': sf(row.get('SpeedDecay')),
            'tilt': str(row['Tilt']) if 'Tilt' in row.index and pd.notna(row.get('Tilt')) else None,
        })
    return jsonify(results)

@app.route('/ai_comment', methods=['GET'])
def ai_comment():
    import requests as req_lib
    target_name = (request.args.get('player_name') or "").strip()
    target_year  = (request.args.get('year')        or "すべて").strip()
    target_date  = (request.args.get('date')        or "すべて").strip()
    question     = (request.args.get('question')    or "").strip()

    api_key = os.environ.get('ANTHROPIC_API_KEY', '')
    if not api_key:
        return jsonify({'error': 'ANTHROPIC_API_KEY が環境変数に設定されていません'})

    df = get_data()
    if df.empty:
        return jsonify({'error': 'データがありません'})
    if target_name:
        df = df[df['display_name'] == target_name]
    if target_year != "すべて":
        df = df[df['year_str'] == target_year]
    if target_date != "すべて":
        df = df[df['date_clean'] == target_date]
    if df.empty:
        return jsonify({'error': '該当データがありません'})

    p_col = 'TaggedPitchType' if 'TaggedPitchType' in df.columns else 'PitchType'
    metrics_cols = ['RelSpeed', 'SpinRate', 'InducedVertBreak', 'HorzBreak',
                    'Extension', 'EffVelocity', 'SpeedDecay', 'RelHeight', 'RelSide']

    lines = []
    order = PITCH_ORDER + [p for p in df[p_col].dropna().unique() if p not in PITCH_ORDER]
    for pt in order:
        sub = df[df[p_col] == pt]
        if len(sub) == 0:
            continue
        parts = [f"球種: {pt}  投球数: {len(sub)}球"]
        for m in metrics_cols:
            if m in sub.columns:
                vals = sub[m].dropna()
                if len(vals) > 0:
                    parts.append(f"{m}=avg{vals.mean():.1f} max{vals.max():.1f} min{vals.min():.1f}")
        lines.append(" / ".join(parts))

    date_info = f"日付: {target_date}" if target_date != "すべて" else f"期間: {target_year} シーズン全体"
    summary = "\n".join(lines)

    prompt = f"""あなたはプロ野球専門のピッチングコーチです。以下の投球計測データを分析してください。

選手: {target_name}
{date_info}

【投球データ（Trackman）】
{summary}

コーチング視点で日本語で3〜5項目の箇条書きコメントを作成してください。
各球種の球速・回転数・変化量の評価、強みと改善ポイント、注目すべき傾向を具体的な数値を引用しながら簡潔に記述してください。"""

    if question:
        prompt += f"\n\n【特に注目してほしい点】\n{question}"

    try:
        resp = req_lib.post(
            'https://api.anthropic.com/v1/messages',
            headers={
                'x-api-key': api_key,
                'anthropic-version': '2023-06-01',
                'content-type': 'application/json',
            },
            json={
                'model': 'claude-haiku-4-5-20251001',
                'max_tokens': 1024,
                'messages': [{'role': 'user', 'content': prompt}],
            },
            timeout=30,
        )
        if resp.status_code == 200:
            return jsonify({'comment': resp.json()['content'][0]['text']})
        else:
            return jsonify({'error': f'APIエラー: {resp.status_code}'})
    except Exception as e:
        return jsonify({'error': f'通信エラー: {e}'})

@app.route('/', defaults={'path': ''})
@app.route('/<path:path>')
def serve_flutter(path):
    web_dir = os.path.join(BASE_DIR, 'build', 'web')
    if path and os.path.exists(os.path.join(web_dir, path)):
        return send_from_directory(web_dir, path)
    return send_from_directory(web_dir, 'index.html')

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 5003))
    app.run(debug=False, host='0.0.0.0', port=port)