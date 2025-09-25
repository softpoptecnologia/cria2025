# mqtt_worker.py
import os, json, signal, sys
from datetime import datetime, timezone
import paho.mqtt.client as mqtt
from dotenv import load_dotenv
from db import one, exec_

load_dotenv()
SITE = os.getenv("SITE", "default")
LINE_ID = os.getenv("LINE_ID", "1")
MQTT_HOST = os.getenv("MQTT_HOST", "127.0.0.1")
MQTT_PORT = int(os.getenv("MQTT_PORT", "1883"))
MQTT_USER = os.getenv("MQTT_USER")
MQTT_PASS = os.getenv("MQTT_PASS")

TOPIC_EVENTS = f"factory/{SITE}/line/{LINE_ID}/device/+/event"
TOPIC_STATUS = f"factory/{SITE}/line/{LINE_ID}/device/+/status"  # opcional

_cache_disp = {}

def _disp_id(codigo: str):
    if codigo in _cache_disp:
        return _cache_disp[codigo]
    r = one("SELECT id FROM dispositivos WHERE codigo=:c", c=codigo)
    if not r:
        return None
    _cache_disp[codigo] = r["id"]
    return _cache_disp[codigo]

def on_connect(client, userdata, flags, rc, properties=None):
    print("[MQTT] conectado rc=", rc)
    client.subscribe(TOPIC_EVENTS, qos=1)
    client.subscribe(TOPIC_STATUS, qos=1)

def on_message(client, userdata, msg):
    topic = msg.topic
    try:
        payload = json.loads(msg.payload.decode("utf-8"))
    except Exception:
        payload = msg.payload.decode("utf-8")

    parts = topic.split("/")  # factory/{SITE}/line/{LINE_ID}/device/{CODIGO}/(event|status)
    codigo = parts[6] if len(parts) >= 7 else None
    if not codigo:
        print("[MQTT] tópico inesperado:", topic)
        return

    did = _disp_id(codigo)
    if not did:
        print("[MQTT] dispositivo desconhecido:", codigo)
        return

    if topic.endswith("/event"):
        if not isinstance(payload, dict):
            print("[MQTT] payload inválido em event:", payload)
            return

        t = payload.get("type")
        if t == "count_delta":
            sessao_id = payload.get("sessao_id")
            delta = int(payload.get("delta", 0))
            ts = payload.get("ts")
            if not sessao_id or delta == 0:
                return
            try:
                when = (
                    datetime.fromisoformat(ts.replace("Z", ""))
                    if ts else datetime.now(timezone.utc).replace(tzinfo=None)
                )
            except Exception:
                when = datetime.now(timezone.utc).replace(tzinfo=None)

            exec_("""
                INSERT INTO leituras (sessao_id, dispositivo_id, timestamp, contagem_incremental, temperatura_c)
                VALUES (:sessao_id, :dispositivo_id, :ts, :delta, NULL)
            """, sessao_id=sessao_id, dispositivo_id=did, ts=when, delta=delta)

        elif t == "heartbeat":
            # opcional: salvar em eventos_alerta ou ignorar
            pass

        elif t == "summary":
            # opcional: gerar log/alerta de fechamento
            pass

    elif topic.endswith("/status"):
        # status "online"/"offline" (LWT). Opcional: gravar alerta.
        status = (payload or "").strip().lower() if isinstance(payload, str) else str(payload)
        # se quiser vincular a uma sessão ativa, procure a última sessão 'ativa' deste device (não obrigatório)
        # Exemplo: gravar alerta simples sem vincular:
        if status in ("offline", "online"):
            msg_alerta = f"Dispositivo {codigo} ficou {status}"
            print("[STATUS]", msg_alerta)
            # Se quiser vincular a uma sessão ativa e inserir em eventos_alerta, descomente:
            # s = one("""SELECT id FROM sessoes_producao
            #            WHERE status='ativa'
            #              AND id = (SELECT MAX(id) FROM sessoes_producao WHERE status='ativa')""")
            # if s:
            #     exec_("INSERT INTO eventos_alerta (sessao_id, tipo, mensagem) VALUES (:sid,:t,:m)",
            #           sid=s["id"], t=f"device_{status}", m=msg_alerta)

def main():
    client = mqtt.Client(client_id="flask-mqtt-consumer", clean_session=True)
    if MQTT_USER:
        client.username_pw_set(MQTT_USER, MQTT_PASS)
    client.on_connect = on_connect
    client.on_message = on_message
    client.connect(MQTT_HOST, MQTT_PORT, 30)

    def _sig(*args):
        client.disconnect()
        sys.exit(0)

    signal.signal(signal.SIGINT, _sig)
    signal.signal(signal.SIGTERM, _sig)
    client.loop_forever()

if __name__ == "__main__":
    main()
