<div align="center">

<img src="assets/banner.svg" alt="Supercleaner — Clean it all. Get your disk back." width="100%">

<br>

![License](https://img.shields.io/badge/license-Apache--2.0-7c3aed?style=for-the-badge)
![Dry run first](https://img.shields.io/badge/dry_run-by_default-22c55e?style=for-the-badge)
![Zero dependencies](https://img.shields.io/badge/dependencies-zero-ec4899?style=for-the-badge)
![macOS + Linux](https://img.shields.io/badge/macOS_%7C_Linux-bash_3.2%2B-f59e0b?style=for-the-badge)

### 🧹 One command to sweep away `node_modules`, build output, Expo native folders, the Next.js cache and Docker junk.

</div>

---

## ✨ Why Supercleaner?

Every JS project quietly hoards gigabytes. Ten projects later your disk is at 98%, Docker Desktop refuses to start, and you are deleting folders by hand. **Supercleaner finds the regenerable stuff, shows you exactly what it would delete, and only then — if you say so — sweeps it away.**

| | |
|---|---|
| 🛡️ **Safe by default** | Always a dry run. Nothing is deleted without `--yes`. |
| 🎯 **Smart, not blunt** | A `build/` or `ios/` folder is only removed when a project marker proves it is generated output, so your `src/build/` is never touched. |
| 📱 **Expo-aware** | `ios/` and `android/` go only inside Expo projects, where `expo prebuild` recreates them. |
| 🐳 **Docker too** | Optional pruning of stopped containers, dangling images and build cache. **Volumes are never touched.** |
| 🪶 **Zero dependencies** | One bash script. Works on macOS's stock bash 3.2. |

## 🎨 What it cleans

| Target | Removed when | Brought back by |
|---|---|---|
| 📦 `node_modules` | always | `npm install` / `pnpm install` / `yarn` |
| ⚡ `.next` | next to a `package.json` | `next build` / `next dev` |
| 🏗️ `build` | next to a `package.json` | your build script |
| 🍎 `ios` · 🤖 `android` | next to a `package.json` **and** `app.json` / `app.config.*` (Expo managed) | `npx expo prebuild` |
| 🐳 Docker *(opt-in)* | `--docker` | pulled or rebuilt on demand |

`.git` folders are never entered, and anything inside an already-selected folder is skipped, so sizes are never counted twice.

## 🚀 Quick start

```bash
git clone git@github.com:thomashagstrom/superclean.git
cd superclean
```

Scan a folder (this is only a preview — nothing is deleted):

```bash
npm run clean -- ~/Source
```

Happy with the list? Sweep it:

```bash
npm run clean:yes -- ~/Source
```

Or run it straight from GitHub without cloning:

```bash
npx github:thomashagstrom/superclean ~/Source
```

With no path, Supercleaner scans the directory you are standing in.

## 🐳 Docker

```bash
npm run clean:docker -- ~/Source    # preview + Docker disk usage
npm run clean:all -- ~/Source       # folders AND Docker: prune for real
```

`--docker` removes stopped containers, unused networks, dangling images and build cache. `--docker-all` also removes every image no container is using. Volumes hold your data and are **never** pruned.

If Docker Desktop's engine is stopped or crashed (a full disk is a common cause), Supercleaner gives up after 15 seconds with a clear message instead of hanging.

## 🧰 All options

| Command | What it does |
|---|---|
| `superclean [path]` | Preview what would be removed (default: current directory) |
| `superclean [path] --yes` | Actually delete it |
| `superclean [path] --docker` | Also show Docker disk usage; with `--yes`, prune it |
| `superclean [path] --docker-all` | Like `--docker`, but remove all unused images too |
| `superclean --help` | Show usage |

| npm script | Same as |
|---|---|
| `npm run clean` | `superclean` |
| `npm run clean:yes` | `superclean --yes` |
| `npm run clean:docker` | `superclean --docker` |
| `npm run clean:all` | `superclean --docker --yes` |

Pass the folder after `--`, e.g. `npm run clean -- ~/Source`.

## 💡 Good to know

- **pnpm sizes are an upper bound.** pnpm fills `node_modules` from a shared store using copy-on-write clones on macOS, so a 3 GB `node_modules` may free far less than 3 GB. Run `pnpm store prune` to clear packages no project uses any more.
- **Cleaned a project?** Reinstall before you build or test it. Git worktrees each carry their own `node_modules`.
- **Hand-edited `ios/` or `android/`?** Those edits are lost. Move them into an Expo config plugin first.

## 🧪 Tests

```bash
npm test
```

Builds a throwaway project tree and checks both what gets removed and, just as important, what is kept.

## 📄 License

[Apache-2.0](LICENSE) — free to use, share and improve. Stars and pull requests are very welcome ⭐
