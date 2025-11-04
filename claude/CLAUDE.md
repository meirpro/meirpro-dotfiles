- Check TypeScript and linting at the end of your changes each time to make sure things still work. Linting issues are suggestions and recommended to follow, but sometimes they might be incorrect.
- Don't use placeholder or "coming soon" code - always implement full functionality.
- **NEVER include these lines in commit messages:**
  ```
  🤖 Generated with [Claude Code](https://claude.ai/code)

  Co-Authored-By: Claude <noreply@anthropic.com>
  ```
- **File path handling**: When the user provides a file or image path (especially relative macOS paths like `~/Desktop/screenshot.png` or `Documents/file.txt`), always use the Read tool to access the file. Don't assume or guess the content - explicitly read it first.