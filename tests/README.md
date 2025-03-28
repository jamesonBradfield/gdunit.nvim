## Development and Testing

### Running Tests

This plugin uses [Busted](https://lunarmodules.github.io/busted/) for unit testing. To run the tests:

1. Make sure you have [Node.js](https://nodejs.org/) installed (for npm)
2. Run the tests using the npm script:

```bash
npm test
```

### Watch Mode for Development

During development, you can use watch mode to automatically run tests when files change:

```bash
npm run test:watch
```

This requires the `entr` utility to be installed:
- On macOS: `brew install entr`
- On Ubuntu/Debian: `apt-get install entr`
- On Arch Linux: `pacman -S entr`

### Test Structure

- `tests/busted.lua` - Test runner setup
- `tests/test_helper.lua` - Common test utilities and mocks
- `tests/*_spec.lua` - Individual test files for each module

### Adding New Tests

1. Create a new test file in the `tests/` directory named `<module>_spec.lua`
2. Add test cases following the existing test structure
3. Run the tests to verify your changes

### Code Coverage

To generate code coverage reports, you'll need LuaCov. Install it with:

```bash
luarocks install luacov
```

Then run tests with coverage:

```bash
nvim -l ./tests/busted.lua --coverage tests/
```

A `luacov.report.out` file will be generated with coverage information.
