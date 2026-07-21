#!/usr/bin/env node
// Imprime todas las migraciones SQL de supabase/migrations en orden,
// para copiar y pegar en el editor SQL de Supabase.
//
// Uso:
//   node scripts/print-migrations.mjs              # imprime todo en consola
//   node scripts/print-migrations.mjs > all.sql    # vuelca a un archivo
//   node scripts/print-migrations.mjs 008 012      # solo un rango (inclusive)

import { readdir, readFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import path from 'node:path'

// Salir silenciosamente si el lector cierra el pipe (ej. `| head`).
process.stdout.on('error', (err) => {
  if (err.code === 'EPIPE') process.exit(0)
  throw err
})

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const migrationsDir = path.resolve(__dirname, '..', 'supabase', 'migrations')

// Prefijo numérico del nombre de archivo, ej. "008" de "008_profile_avatars_storage.sql"
const prefixOf = (name) => {
  const match = name.match(/^(\d+)/)
  return match ? Number(match[1]) : Number.POSITIVE_INFINITY
}

const args = process.argv.slice(2)
const from = args.length > 0 ? Number(args[0]) : null
const to = args.length > 1 ? Number(args[1]) : null

const files = (await readdir(migrationsDir))
  .filter((name) => name.endsWith('.sql'))
  .sort((a, b) => prefixOf(a) - prefixOf(b))
  .filter((name) => {
    if (from === null) return true
    const n = prefixOf(name)
    return n >= from && (to === null ? true : n <= to)
  })

if (files.length === 0) {
  console.error('No se encontraron migraciones que coincidan.')
  process.exit(1)
}

for (const name of files) {
  const sql = await readFile(path.join(migrationsDir, name), 'utf8')
  console.log(`-- ============================================================`)
  console.log(`-- Migration: ${name}`)
  console.log(`-- ============================================================`)
  console.log(sql.trimEnd())
  console.log('') // línea en blanco entre migraciones
}
