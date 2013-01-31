test: test.sh
	./test.sh

.PHONY: current
current:
	rm -rf current
	mv new current

clean:
	rm -rf orig new

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
	@echo "[orig] [new] [current]"
	@meld current/$** new/$**
