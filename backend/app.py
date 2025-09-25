# app.py
import os, json, logging
from datetime import datetime, timezone
from flask import Flask, request, jsonify
from flask_cors import CORS
from dotenv import load_dotenv
import paho.mqtt.client as mqtt
from db import one, all_, exec_

load_dotenv()

# --- Config ---
SITE = os.getenv("SITE", "default")
LINE_ID = os.getenv("LINE_ID", "1")
FLASK_HOST = os.getenv("FLASK_HOST", "0.0.0.0")
FLASK_PORT = int(os.getenv("FLASK_PORT", "5000"))
FLASK_DEBUG = os.getenv("FLASK_DEBUG", "false").lower() == "true"

MQTT_HOST = os.getenv("MQTT_HOST", "127.0.0.1")
MQTT_PORT = int(os.getenv("MQTT_PORT", "1883"))
MQTT_USER = os.getenv("MQTT_USER")
MQTT_PASS = os.getenv("MQTT_PASS")

# --- App ---
app = Flask(__name__)
CORS(app, resources={r"/*": {"origins": "*"}})

# logs simples
logging.basicConfig(
    level=logging.INFO if not FLASK_DEBUG else logging.DEBUG,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
log = logging.getLogger("app")

# --- MQTT Publisher ---
mqttc = mqtt.Client(client_id="flask-api-pub", clean_session=True)
if MQTT_USER:
    mqttc.username_pw_set(MQTT_USER, MQTT_PASS)
mqttc.connect(MQTT_HOST, MQTT_PORT, 30)
mqttc.loop_start()

def publish_cmd(dispositivo_codigo, action_or_dict):
    import paho.mqtt.publish as publish
    topic = f"factory/default/line/1/device/{dispositivo_codigo}/cmd"

    # Se for dicionário, transforma em JSON
    if isinstance(action_or_dict, dict):
        payload = json.dumps(action_or_dict)
    else:
        payload = json.dumps({"action": action_or_dict})

    print(f"[MQTT] Publicando em {topic}: {payload}")
    publish.single(
        topic,
        payload=payload,
        hostname=os.getenv("MQTT_HOST", "127.0.0.1"),  # usa variável correta
        port=1883,
    )



# ---------- Util ----------
def now_utc_naive():
    # UTC sem tzinfo (MySQL DATETIME)
    return datetime.now(timezone.utc).replace(tzinfo=None)

# ---------- Health ----------
@app.get("/health")
def health():
    return jsonify({"ok": True, "mysql_db": os.getenv("MYSQL_DB"), "mqtt_host": MQTT_HOST})

# ---------- Listas ----------
@app.get("/clientes")
def listar_clientes():
    rows = all_("SELECT id, nome FROM clientes ORDER BY nome ASC")
    return jsonify(rows)

@app.get("/produtos")
def listar_produtos():
    rows = all_("SELECT id, nome FROM produtos ORDER BY nome ASC")
    return jsonify(rows)

@app.get("/dispositivos")
def listar_dispositivos():
    rows = all_("SELECT id, codigo, COALESCE(descricao,'') AS descricao FROM dispositivos ORDER BY codigo ASC")
    return jsonify(rows)

# ---------- Sessões ----------
@app.post("/sessoes")
def criar_sessao():
    """
    body: {cliente_id, produto_id, lote, operador_id, dispositivo_codigo}
    - Cria registro em sessoes_producao (status='ativa', inicio=now)
    - Publica comando 'start' para o dispositivo
    """
    data = request.get_json(force=True)
    required = ["cliente_id", "produto_id", "operador_id", "dispositivo_codigo"]
    missing = [k for k in required if k not in data]
    if missing:
        return jsonify({"error": f"Campos obrigatórios faltando: {', '.join(missing)}"}), 400

    cliente_id = int(data["cliente_id"])
    produto_id = int(data["produto_id"])
    operador_id = int(data["operador_id"])
    lote = (data.get("lote") or "default").strip()[:255]
    dispositivo_codigo = (data["dispositivo_codigo"] or "").strip()

    disp = one("SELECT id FROM dispositivos WHERE codigo=:c", c=dispositivo_codigo)
    if not disp:
        return jsonify({"error": "dispositivo_codigo inválido"}), 400

    sessao_id = exec_("""
        INSERT INTO sessoes_producao (cliente_id, produto_id, lote, operador_id, inicio, status)
        VALUES (:cliente_id, :produto_id, :lote, :operador_id, :inicio, 'ativa')
    """, cliente_id=cliente_id, produto_id=produto_id, lote=lote,
         operador_id=operador_id, inicio=now_utc_naive())

    publish_cmd(dispositivo_codigo, {"action": "start", "sessao_id": sessao_id})
    return jsonify({"sessao_id": sessao_id}), 201

@app.post("/sessoes/<int:sessao_id>/finalizar")
def finalizar_sessao(sessao_id: int):
    data = request.get_json(force=True)
    dispositivo_codigo = (data.get("dispositivo_codigo") or "").strip()
    if not dispositivo_codigo:
        return jsonify({"error": "dispositivo_codigo obrigatório"}), 400

    exec_("UPDATE sessoes_producao SET fim=:fim, status='finalizada' WHERE id=:id",
          fim=now_utc_naive(), id=sessao_id)

    publish_cmd(dispositivo_codigo, {"action": "stop", "sessao_id": sessao_id})
    return jsonify({"ok": True})

@app.get("/sessoes/<int:sessao_id>")
def obter_sessao(sessao_id: int):
    s = one("""
        SELECT s.id, s.cliente_id, s.produto_id, s.lote, s.operador_id,
               s.inicio, s.fim, s.status, COALESCE(v.total,0) AS total
        FROM sessoes_producao s
        LEFT JOIN vw_totais_sessao v ON v.sessao_id = s.id
        WHERE s.id=:id
    """, id=sessao_id)
    if not s:
        return jsonify({"error": "not found"}), 404

    # últimas 20 leituras
    l = all_("""SELECT timestamp, contagem_incremental
                FROM leituras
                WHERE sessao_id=:id
                ORDER BY id DESC
                LIMIT 20""", id=sessao_id)
    s["ultimas_leituras"] = list(reversed(l))
    return jsonify(s)

@app.get("/sessoes")
def listar_sessoes():
    # paginação simples ?page=1&size=20
    try:
        page = max(1, int(request.args.get("page", "1")))
        size = min(100, max(1, int(request.args.get("size", "20"))))
    except Exception:
        page, size = 1, 20
    offset = (page - 1) * size

    rows = all_("""SELECT s.id, s.status, s.inicio, s.fim,
                          c.nome AS cliente, p.nome AS produto,
                          COALESCE(v.total,0) AS total
                   FROM sessoes_producao s
                   JOIN clientes c ON c.id=s.cliente_id
                   JOIN produtos p ON p.id=s.produto_id
                   LEFT JOIN vw_totais_sessao v ON v.sessao_id=s.id
                   ORDER BY s.id DESC
                   LIMIT :size OFFSET :off""", size=size, off=offset)

    return jsonify({"page": page, "size": size, "rows": rows})


from sqlalchemy.exc import OperationalError

@app.post("/leituras")
def registrar_leitura():
    """
    body: {sessao_id: int, device_code: str, inc: int, ts?: str}
    """
    data = request.get_json(force=True)

    try:
        sessao_id = int(data.get("sessao_id") or 0)
        inc = int(data.get("inc") or 0)
        device_code = (data.get("device_code") or "").strip()
    except Exception:
        return jsonify({"error": "json inválido"}), 400

    if sessao_id <= 0 or inc <= 0:
        return jsonify({"error": "sessao_id e inc precisam ser > 0"}), 400

    # Confirma sessão
    s = one("SELECT id, status FROM sessoes_producao WHERE id=:id", id=sessao_id)
    if not s:
        return jsonify({"error": "sessao_id inexistente"}), 404

    # Busca o dispositivo pelo código
    disp = one("SELECT id FROM dispositivos WHERE codigo=:c", c=device_code)
    if not disp:
        return jsonify({"error": "device_code desconhecido"}), 400

    # Se você criou a coluna 'dispositivo' (VARCHAR) e quer registrar também o código,
    # insere as DUAS colunas; senão, comente a linha e use apenas dispositivo_id.
    try:
        exec_("""
            INSERT INTO leituras
                (sessao_id, timestamp, contagem_incremental, dispositivo_id, dispositivo)
            VALUES
                (:sessao_id, :ts, :inc, :disp_id, :disp)
        """, sessao_id=sessao_id, ts=now_utc_naive(), inc=inc,
             disp_id=disp["id"], disp=device_code)
    except OperationalError as e:
        # Se a coluna 'dispositivo' (VARCHAR) não existir nesse ambiente, grava sem ela:
        if "Unknown column 'dispositivo'" in str(e):
            exec_("""
                INSERT INTO leituras
                    (sessao_id, timestamp, contagem_incremental, dispositivo_id)
                VALUES
                    (:sessao_id, :ts, :inc, :disp_id)
            """, sessao_id=sessao_id, ts=now_utc_naive(), inc=inc, disp_id=disp["id"])
        else:
            raise

    return jsonify({"ok": True, "sessao_id": sessao_id, "inc": inc})



if __name__ == "__main__":
    app.run(host=FLASK_HOST, port=FLASK_PORT, debug=FLASK_DEBUG)
