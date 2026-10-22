extends RefCounted
## Which build this is. tools/export-web.mjs writes the git commit here while exporting and then
## puts "dev" back, so the title and pause screens can show players what version they are running.

const VERSION := "dev"
