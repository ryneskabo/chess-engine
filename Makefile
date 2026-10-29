.PHONY: workspace attach clean

workspace: clean
	zellij --session engine --new-session-with-layout ./dev.kdl

attach:
	zellij attach engine

clean:
	-zellij delete-session --force engine 2>/dev/null
