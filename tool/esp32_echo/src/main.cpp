// Echo firmware for testing usb_serial_next.
//
// Commands, one per line:
//   ping        -> pong
//   info        -> chip, CPU clock, uptime
//   burst N     -> N letters A..Z as fast as possible, then "burst done N"
//   sink N      -> reads N bytes, then "sink done <got> in <ms> ms"
//   anything    -> "echo: anything"
#include <Arduino.h>

static String line;

static void burst(long count) {
  static uint8_t chunk[1024];
  for (long sent = 0; sent < count;) {
    const size_t n = min<long>(sizeof(chunk), count - sent);
    for (size_t i = 0; i < n; i++) chunk[i] = 'A' + (sent + i) % 26;
    Serial.write(chunk, n);
    sent += n;
  }
  Serial.printf("\nburst done %ld\n", count);
}

static void sink(long count) {
  static uint8_t buffer[4096];
  long got = 0;
  const uint32_t start = millis();
  uint32_t last = start;
  // Gives up after 3 s without data, so a short write does not hang it.
  while (got < count && millis() - last < 3000) {
    const int available = Serial.available();
    if (available <= 0) continue;
    const size_t want = min<long>(min<long>(available, sizeof(buffer)), count - got);
    got += Serial.read(buffer, want);
    last = millis();
  }
  Serial.printf("sink done %ld in %lu ms\n", got, last - start);
}

static void handle(const String& command) {
  if (command == "ping") {
    Serial.println("pong");
  } else if (command == "info") {
    Serial.printf("%s rev %d, %u MHz, up %lu ms\n", ESP.getChipModel(),
                  ESP.getChipRevision(), ESP.getCpuFreqMHz(), millis());
  } else if (command.startsWith("burst ")) {
    burst(command.substring(6).toInt());
  } else if (command.startsWith("sink ")) {
    sink(command.substring(5).toInt());
  } else {
    Serial.print("echo: ");
    Serial.println(command);
  }
}

void setup() {
  Serial.setRxBufferSize(65536);
  Serial.setTxBufferSize(4096);
#if ARDUINO_USB_MODE && ARDUINO_USB_CDC_ON_BOOT
  // Native USB: wait for a slow host instead of dropping data.
  Serial.setTxTimeoutMs(2000);
#endif
  Serial.begin(115200);
  delay(300);
  Serial.println("usb_serial_next echo ready");
}

void loop() {
  while (Serial.available()) {
    const char c = Serial.read();
    if (c == '\n' || c == '\r') {
      if (line.length()) handle(line);
      line = "";
    } else if (line.length() < 256) {
      line += c;
    }
  }
}
