# orgo

Run [Claude Code](https://claude.com/claude-code) on [OpenRouter](https://openrouter.ai) and let it **pick the best value model for each task**.

Type `orgo` in your terminal and it:

1. 📋 Reads your project's `HANDOFF.md` (or asks you for tasks)
2. 💸 Pulls live OpenRouter prices for every model that can run Claude Code
3. 🧠 Checks current benchmarks and picks a model **per task**: a top model for hard work, a cheap one for easy work
4. 🗺️ Shows you the plan and waits for your OK (you can swap any model)
5. ▶️ Runs the tasks one by one at **max effort**, each updating `HANDOFF.md` when done

Example plan:

```
1) Build the settings page        🤖 openai/gpt-6-astra             ~$1.20
2) Fix login redirect bug          🤖 xiaomi/mimo-v2.6-pro           ~$0.50
3) Write README setup section      🤖 deepseek/deepseek-v4.1-flash   ~$0.02
```

Handy when your Claude plan runs out for the week, or when you want to stop paying frontier prices for easy tasks.

## Install (macOS)

You need Claude Code and an [OpenRouter API key](https://openrouter.ai/settings/keys). Tip: give the key a monthly spend limit.

```bash
curl -fsSL https://raw.githubusercontent.com/aidan-edwards/orgo/main/install.sh | bash
```

It asks 4 questions: the command name (default `orgo`), your projects folder, your key and whether to sandbox. Then open a new Terminal window.

## Use

```bash
orgo              # pick a project
orgo my-app       # jump straight into ~/orgo-workspace/my-app
```

If the project is a git repo, orgo pulls the latest work first and offers to switch to the branch with the newest commits.

## Safety

- 🔑 Your key lives in the macOS Keychain, never in a file
- 🟢 A status line shows `OPENROUTER · model` the whole session, and every request goes to OpenRouter (nothing is billed to the Anthropic API)
- 🚫 Anthropic models are excluded so you don't pay twice if you have a Claude plan
- 🧱 Optional sandbox (on by default, no password): sessions can only write inside the project folder and can't read the rest of your home folder
- 👀 Nothing runs until you approve the plan

## Settings

Edit `~/.orgo/config` to change the planner model, the fallback model or extra Claude Code flags (for example `ORGO_EXTRA_ARGS="--chrome"`).

## Uninstall

```bash
rm -rf ~/.orgo && sed -i '' '/# >>> orgo >>>/,/# <<< orgo <<</d' ~/.zshrc && security delete-generic-password -s orgo-openrouter-key
```

## Notes

- Model prices and benchmarks change constantly, so the planner looks them up fresh every run.
- Whether "max effort" is honored depends on each model and provider.
- MIT licensed. Not affiliated with Anthropic or OpenRouter.
