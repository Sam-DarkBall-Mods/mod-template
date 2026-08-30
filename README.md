# Arma 3 mod template

[![CI](https://github.com/Sam-DarkBall-Mods/mod-template/actions/workflows/ci.yml/badge.svg)](https://github.com/Sam-DarkBall-Mods/mod-template/actions/workflows/ci.yml)

This is the starting point for new Sam-DarkBall-Mods projects. It contains the
HEMTT config, CI workflows, release checks, licenses and the basic repository
tests used by the existing mods.

Create a repository from this template, replace the example addon and update
the project name, prefix and release folder in `.hemtt/project.toml`.

## What you need

- Arma 3 2.22 or newer
- [HEMTT](https://hemtt.dev/) 1.21 or newer

## Local checks

```bash
python3 -B tools/validate_repository.py
python3 -B -m unittest discover -s tests -p "test_*.py" -v
hemtt check
hemtt build --no-bin
```

The local build skips BI binarization. The Windows release job uses Arma 3
Tools and produces the files intended for distribution.

## License

SQF, Arma configs and repository tooling use GPL-2.0-or-later. Original game
assets use APL-SA. See [LICENSES.md](LICENSES.md) for the split.
