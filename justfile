default:
  @just --list

server:
  hugo server

build:
  hugo build --gc --minify
