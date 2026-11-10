// Renders the page to static HTML after both Vite builds, so the content is in
// dist/index.html for search engines, link previews and readers without script.
import { readFile, rm, writeFile } from 'node:fs/promises'
import { fileURLToPath, pathToFileURL } from 'node:url'

const root = fileURLToPath(new URL('..', import.meta.url))
const htmlPath = `${root}dist/index.html`
const { render } = await import(pathToFileURL(`${root}dist-ssr/entry-server.js`).href)

const template = await readFile(htmlPath, 'utf8')
if (!template.includes('<!--app-->')) throw new Error('dist/index.html has no <!--app--> marker')

await writeFile(htmlPath, template.replace('<!--app-->', render()))
await rm(`${root}dist-ssr`, { recursive: true, force: true })
console.log('prerendered dist/index.html')
