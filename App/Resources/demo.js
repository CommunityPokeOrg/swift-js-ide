// Welcome to PokeIDE — a JavaScript IDE for macOS & iPadOS.
// Press Run (⌘R) to execute this script with JavaScriptCore.

const fib = (n) => (n < 2 ? n : fib(n - 1) + fib(n - 2));

console.log("Fibonacci:");
for (let i = 0; i < 10; i++) {
    console.log(`fib(${i}) = ${fib(i)}`);
}

const palette = { name: "pokeide", accent: "#F7DF1E", platforms: ["macOS", "iPadOS"] };
console.info("Config:", palette);
console.warn("This is a warning — diagnostics show up in Problems too.");

try {
    const re = /poke-(\w+)/;
    console.log("Regex match:", "poke-ide".match(re)[1]);
    console.debug("Debug lines render in purple.");
} catch (error) {
    console.error(error);
}

// Top-level result appears as `⇒ value` in the console.
`Computed ${fib(15)}`;
