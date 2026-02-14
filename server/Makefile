BINARY = deadkbd-server
SIGN_ID = Apple Development: Oleksii Ilienko (4SDS4B9AK9)

.PHONY: build run clean

build:
	go build -ldflags="-s -w" -o $(BINARY) .
	codesign -s "$(SIGN_ID)" --entitlements entitlements.plist --force ./$(BINARY)

run: build
	./$(BINARY) --password $(PASSWORD) --port $(or $(PORT),9877)

clean:
	rm -f $(BINARY)
