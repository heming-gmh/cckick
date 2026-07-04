# ccpoint 是纯 shell,没有构建步骤。Makefile 只提供 install/test 的统一入口。

.PHONY: help install test clean

help:
	@echo "ccpoint — make targets:"
	@echo "  make install   打印该加到 ~/.zshrc 的 source 行"
	@echo "  make test      跑 tests/"
	@echo "  make clean     清理 zsh 编译产物 (*.zwc)"

install:
	@echo ""
	@echo "把下面这行加到 ~/.zshrc(然后重开终端):"
	@echo "  source $(CURDIR)/ccpoint.plugin.zsh"
	@echo ""
	@echo "或用插件管理器(oh-my-zsh / zplug / zinit)加载本目录。"
	@echo "provider 配置:$$\{XDG_CONFIG_HOME:-~/.config}/ccpoint/providers/*.zsh(见 ccpoint.example.zsh / examples/)"

test:
	@zsh tests/run.zsh

clean:
	@rm -f *.zwc **/*.zwc 2>/dev/null || true
