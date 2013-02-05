test: test.sh
	./test.sh

.PHONY: current
current:
	rm -rf current
	mv new current

clean:
	rm -rf orig new tuareg

%.test: test.sh
	./test.sh $*

%.meld: %.test
	@echo
	@echo "Meld view:"
	@echo "[orig] [new] [current]"
	@meld orig/$** new/$** current/$**

%.meld-changes: %.test
	@echo
	@echo "Meld view:"
	@echo "[current] [new]"
	@meld current/$** new/$**

status.html: test.sh
	./test.sh | aha --black -t "ocp-indent current status" > $@
