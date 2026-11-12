.PHONY: run install build export

# Install dependencies only if node_modules is missing
node_modules: package.json package-lock.json
	npm install
	@touch node_modules

install: node_modules

# Start the presentation (Slidev dev server, opens the browser at http://localhost:3030)
run: node_modules
	npm run dev

# Build a static site into dist/
build: node_modules
	npm run build

# Export the slides to PDF
export: node_modules
	npm run export
