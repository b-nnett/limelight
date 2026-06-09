.PHONY: check test test-swift test-python test-typescript typecheck-typescript build-swift clean

check: test typecheck-typescript

test: test-swift test-python test-typescript

test-swift:
	swift test

test-python:
	python3 -m unittest discover -s clients/python/tests

test-typescript:
	cd clients/typescript && npm ci && npm test

typecheck-typescript:
	cd clients/typescript && test -d node_modules || npm ci
	cd clients/typescript && npm run typecheck

build-swift:
	swift build

clean:
	rm -rf .build dist clients/typescript/dist clients/typescript/dist-test
