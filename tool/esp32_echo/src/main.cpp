// Echo firmware for testing usb_serial_next.
//
// Commands, one per line:
//   ping        -> pong
//   info        -> chip, CPU clock, uptime
//   burst N     -> N letters A..Z without pauses, then "burst done N"
//   anything    -> "echo: anything"
#include <Arduino.h>

static String line;

static void handle(const String& command) {
  if (command == "ping") {
    Serial.println("pong");
  } else if (command == "info") {
    Serial.printf("%s rev %d, %u MHz, up %lu ms\n", ESP.getChipModel(),
                  ESP.getChipRevision(), ESP.getCpuFreqMHz(), millis());
  } else if (command.startsWith("burst ")) {
    const long count = command.substring(6).toInt();
    for (long i = 0; i < count; i++) Serial.write('A' + i % 26);
    Serial.printf("\nburst done %ld\n", count);
  } else {
    Serial.print("echo: ");
    Serial.println(command);
  }
}

void setup() {
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
