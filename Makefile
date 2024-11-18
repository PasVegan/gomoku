##
## EPITECH PROJECT, 2022
## Makefile
## File description:
## Makefile
##

NAME = pbrain-gomoku-ai

ARCHIVE := zig-linux-x86_64-0.14.0-dev.1911+3bf89f55c.tar.gz

EXPECTED_OUTPUTS := zig-linux-x86_64-0.14.0-dev.1911+3bf89f55c/zig

# Default target
all: $(EXPECTED_OUTPUTS)
	@$(EXPECTED_OUTPUTS) build -p . --prefix-exe-dir . -Doptimize=ReleaseFast

debug: $(EXPECTED_OUTPUTS)
	@$(EXPECTED_OUTPUTS) build -p . --prefix-exe-dir . -Doptimize=Debug

tests_run: $(EXPECTED_OUTPUTS)
	@$(EXPECTED_OUTPUTS) build coverage --summary all

# Rule to check each expected output and extract the tar.gz if any are missing
$(EXPECTED_OUTPUTS):
	@if [ ! -e $@ ]; then \
	    echo "Extracting Zig compiler ..."; \
	    tar -x --gz -f $(ARCHIVE); \
	fi

clean:
	@rm -rf zig-cache

fclean: clean
	@find . -name $(NAME) -delete
	@echo "Cleaning up..."
	@rm -rf zig-linux-x86_64-0.13.0
	@rm -rf zig-out

re:	fclean all


.PHONY: all debug clean fclean re
