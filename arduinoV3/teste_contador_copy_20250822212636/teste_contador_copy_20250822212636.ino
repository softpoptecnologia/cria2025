#include <WiFi.h>
#include <PubSubClient.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>

// ---------- REDE / MQTT ----------
const char* ssid         = "SoftpopTecnologia1";
const char* password     = "ailsongomes@#$";
const char* mqtt_server  = "192.168.11.104";
const uint16_t mqtt_port = 1883;
const char* device_code  = "esteira1";

// ---------- API ----------
const char* api_host  = "192.168.11.104";
const uint16_t api_port = 5000;
const char* api_path = "/leituras";

// ---------- ULTRASSÔNICO ----------
const int TRIG_PIN = 26;
const int ECHO_PIN = 25;                 // usar divisor no ECHO (5V -> ~3.3V)
const uint32_t PULSE_TIMEOUT_US = 6000;  // ~1 m (mais rápido)

// Amostragem e limiares
const uint16_t SAMPLE_MS        = 25;    // taxa de amostragem (ms)
const float    threshold_in_cm  = 20.0;  // presente se <= 20 cm
const float    threshold_out_cm = 25.0;  // ausente  se >= 25 cm

// Anti-ruído / anti-dupla-contagem (MODO RÁPIDO)
const uint8_t  IN_CONSENSUS     = 2;     // leituras seguidas para ENTRADA
const uint8_t  OUT_CONSENSUS    = 2;     // leituras seguidas para SAÍDA
const uint32_t MIN_PRESENT_MS   = 20;    // presença mínima antes da saída
const uint32_t REFRACT_MS       = 120;   // refratário após contar
const float    ALPHA            = 0.75;  // suavização (0–1)

// ---------- ESTADOS DO SENSOR ----------
bool objectPresent    = false;
uint32_t lastSampleMs = 0;
uint32_t presentSince = 0;
uint32_t lockoutUntil = 0;
uint8_t  inHits = 0, outHits = 0;
float    smoothD = -1.0;

// ---------- CONTROLE DE SESSÃO ----------
volatile bool countingEnabled = false;
uint32_t sessao_id = 0;

// ---------- ENVIO EM LOTE ----------
uint32_t bufferCount = 0;
const uint32_t BATCH_SIZE = 10;
const uint32_t BATCH_MS   = 2000;
uint32_t lastSendMs = 0;

// ---------- MQTT ----------
WiFiClient wifiClient;
PubSubClient client(wifiClient);
String topic_cmd;

// ---------- Utils ----------
String apiURL() {
  String url = "http://";
  url += api_host; url += ":"; url += String(api_port); url += api_path;
  return url;
}

bool postBatch(uint32_t inc) {
  if (inc == 0 || sessao_id == 0) return true;
  if (WiFi.status() != WL_CONNECTED) return false;

  HTTPClient http;
  http.begin(apiURL());
  http.addHeader("Content-Type", "application/json");

  StaticJsonDocument<256> doc;
  doc["sessao_id"]   = sessao_id;
  doc["device_code"] = device_code;
  doc["inc"]         = inc;
  doc["ts"]          = "";

  String payload; serializeJson(doc, payload);
  int code = http.POST(payload);
  if (code > 0) {
    String resp = http.getString();
    Serial.printf("[API] POST => %d | %s\n", code, resp.c_str());
  } else {
    Serial.printf("[API] POST falhou: %s\n", http.errorToString(code).c_str());
  }
  http.end();
  return (code >= 200 && code < 300);
}

void flushBufferIfNeeded(bool force = false) {
  uint32_t now = millis();
  if (force || bufferCount >= BATCH_SIZE || (now - lastSendMs) >= BATCH_MS) {
    uint32_t toSend = bufferCount;
    bufferCount = 0;
    if (toSend > 0) {
      bool ok = postBatch(toSend);
      if (!ok) bufferCount += toSend;
      else lastSendMs = now;
    } else {
      lastSendMs = now;
    }
  }
}

void handleStart(uint32_t s_id) {
  sessao_id = s_id;
  countingEnabled = true;
  bufferCount = 0;
  objectPresent = false;
  inHits = outHits = 0;
  smoothD = -1.0;
  lockoutUntil = 0;
  lastSendMs = millis();
  Serial.printf(">>> START sessao_id=%u\n", sessao_id);
}

void handleStop(uint32_t s_id) {
  countingEnabled = false;
  Serial.printf(">>> STOP sessao_id=%u (flush final)\n", s_id);
  flushBufferIfNeeded(true);
  sessao_id = 0;
}

// Mede distância em cm (retorna negativo se falhar)
float measureDistanceCm() {
  digitalWrite(TRIG_PIN, LOW);
  delayMicroseconds(2);
  digitalWrite(TRIG_PIN, HIGH);
  delayMicroseconds(10);
  digitalWrite(TRIG_PIN, LOW);

  uint32_t t = pulseIn(ECHO_PIN, HIGH, PULSE_TIMEOUT_US);
  if (t == 0) return -1.0;         // timeout
  return (float)t / 58.0;          // ~cm
}

// Contagem rápida: na SAÍDA, com consenso e refratário curtos
void sampleAndCount() {
  if (!countingEnabled) return;

  uint32_t now = millis();
  if ((now - lastSampleMs) < SAMPLE_MS) return;
  lastSampleMs = now;

  float d = measureDistanceCm();
  if (d < 0) return;

  // suavização exponencial rápida
  if (smoothD < 0) smoothD = d;
  else smoothD = ALPHA * d + (1.0f - ALPHA) * smoothD;

  // período refratário
  if (now < lockoutUntil) {
    if (smoothD >= threshold_out_cm) {
      outHits = min<uint8_t>(outHits + 1, OUT_CONSENSUS);
      if (outHits >= OUT_CONSENSUS) {
        objectPresent = false;
        inHits = outHits = 0;
      }
    } else {
      outHits = 0;
    }
    return;
  }

  if (!objectPresent) {
    // ENTRADA (rápida)
    if (smoothD > 0 && smoothD <= threshold_in_cm) {
      inHits = min<uint8_t>(inHits + 1, IN_CONSENSUS);
      if (inHits >= IN_CONSENSUS) {
        objectPresent = true;
        presentSince = now;
        outHits = 0;
      }
    } else {
      inHits = 0;
    }
  } else {
    // SAÍDA (conta aqui)
    if ((now - presentSince) >= MIN_PRESENT_MS && smoothD >= threshold_out_cm) {
      outHits = min<uint8_t>(outHits + 1, OUT_CONSENSUS);
      if (outHits >= OUT_CONSENSUS) {
        bufferCount++;
        Serial.printf("PEÇA++  dist=%.1f cm  buffer=%u\n", smoothD, bufferCount);

        objectPresent = false;
        inHits = outHits = 0;
        lockoutUntil = now + REFRACT_MS;
      }
    } else {
      outHits = 0;
    }
  }
}

// ---------- MQTT ----------
void mqttCallback(char* topic, byte* payload, unsigned int length) {
  String msg; msg.reserve(length);
  for (unsigned int i = 0; i < length; i++) msg += (char)payload[i];
  Serial.printf("📥 MQTT %s | %s\n", topic, msg.c_str());

  StaticJsonDocument<256> doc;
  if (deserializeJson(doc, msg)) {
    Serial.println("JSON inválido.");
    return;
  }
  const char* action = doc["action"] | "";
  uint32_t s_id = doc["sessao_id"] | 0;

  if (strcmp(action, "start") == 0 && s_id > 0)      handleStart(s_id);
  else if (strcmp(action, "stop") == 0 && s_id > 0)  handleStop(s_id);
  else Serial.println("Comando desconhecido ou sessao_id ausente.");
}

void mqttReconnect() {
  while (!client.connected()) {
    Serial.print("🔄 MQTT...");
    String cid = "esp32-" + String(WiFi.macAddress());
    if (client.connect(cid.c_str())) {
      Serial.println("OK");
      client.subscribe(topic_cmd.c_str());
      Serial.printf("🔔 Sub: %s\n", topic_cmd.c_str());
    } else {
      Serial.printf("falha rc=%d, tentando em 2s...\n", client.state());
      delay(2000);
    }
  }
}

// ---------- Setup/Loop ----------
void setup() {
  Serial.begin(115200);

  WiFi.begin(ssid, password);
  Serial.print("🌐 Conectando");
  while (WiFi.status() != WL_CONNECTED) { Serial.print("."); delay(500); }
  Serial.printf("\n📶 Wi-Fi OK: %s\n", WiFi.localIP().toString().c_str());

  pinMode(TRIG_PIN, OUTPUT);
  pinMode(ECHO_PIN, INPUT);  // lembrar do divisor
  digitalWrite(TRIG_PIN, LOW);

  client.setServer(mqtt_server, mqtt_port);
  client.setCallback(mqttCallback);
  topic_cmd = String("factory/default/line/1/device/") + device_code + "/cmd";
}

void loop() {
  if (!client.connected()) mqttReconnect();
  client.loop();

  sampleAndCount();
  flushBufferIfNeeded(false);
}
