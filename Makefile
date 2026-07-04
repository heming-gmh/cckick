# ccpoint is pure shell — no build step. This Makefile just provides
# convenient install / test entry points.

.PHONY: help install test clean

help:
	@echo "ccpoint — make targets:"
	@echo "  make install   print the line to add to ~/.zshrc"
	@echo "  make test      run tests/"
	@echo "  make clean     remove zsh compiled artifacts (*.zwc)"

install:
	@echo ""
	@echo "Add this line to ~/.zshrc (then restart your shell):"
	@echo "  source $(CURDIR)/ccpoint.plugin.zsh"
	@echo ""
	@echo "Or load this directory with a plugin manager (oh-my-zsh / zplug / zinit)."
	@echo "Provider config: ~/.config/ccpoint/providers/ (see ccpoint.example.zsh / examples/)"

test:
	@zsh tests/run.zsh

clean:
	@rm -f *.zwc **/*.zwc 2>/dev/null || true
