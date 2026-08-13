---
paths:
  - "**/*.sol"
---
# Solidity Style Guide — Agent Reference

> Source: Solidity official docs (Style Guide). Adapted from Python PEP 8.
> Priority of consistency: project conventions > this guide > module/function-local consistency. When in doubt, favor readability. Project-specific style guides override this guide.

## Code Layout

### Indentation & Whitespace Method

- Use **4 spaces** per indentation level.
- Spaces preferred over tabs. Never mix tabs and spaces.
- Source file encoding: UTF-8 or ASCII.

### Blank Lines

- Surround **top-level declarations** (contracts, etc.) with **2 blank lines**.
- Surround **function declarations inside a contract** with **1 blank line**.
- Blank lines may be omitted between groups of related one-liners (e.g., abstract stub functions).

### Maximum Line Length

- Suggested max: **120 characters**.
- When wrapping:
  - First argument is NOT attached to the opening parenthesis.
  - Use exactly one extra indent level.
  - Each argument on its own line.
  - Terminating `);` on its own final line.

### Wrapping Examples (correct form)

```solidity
// Function calls
thisFunctionCallIsReallyLong(
    longArgument1,
    longArgument2,
    longArgument3
);

// Assignments
thisIsALongNestedMapping[being][set][toSomeValue] = someFunction(
    argument1,
    argument2,
    argument3,
    argument4
);

// Events (definition + emit)
event LongAndLotsOfArgs(
    address sender,
    address recipient,
    uint256 publicKey,
    uint256 amount,
    bytes32[] options
);
emit LongAndLotsOfArgs(
    sender,
    recipient,
    publicKey,
    amount,
    options
);
```

### Imports

- All `import` statements go at the **top of the file** (after pragma).

## Order of Layout

### File-level order

1. Pragma statements
2. Import statements
3. Events
4. Errors
5. Interfaces
6. Libraries
7. Contracts

### Inside a contract / library / interface

1. Type declarations
2. State variables
3. Events
4. Errors
5. Modifiers
6. Functions

> Note: It can be clearer to declare types close to their use in events/state variables.

## Order of Functions

Group by visibility in this order:

1. `constructor`
2. `receive` (if present)
3. `fallback` (if present)
4. `external`
5. `public`
6. `internal`
7. `private`

- Within each group, place **`view` and `pure` functions last**.

## Whitespace in Expressions

- **No** extra space immediately inside `()`, `[]`, `{}` — except single-line function declarations.
  - Yes: `spam(ham[1], Coin({name: "ham"}));`
  - Exception: `function singleLine() public { spam(); }`
- **No** space before a comma or semicolon.
- Do **not** add multiple spaces to align assignments/operators.
- No space in `receive()`/`fallback()` (not `receive ()`).
- Surround operators with a single space on each side: `x = 100 / 10;`, `x += 3 + 4;`.
- Higher-precedence operators MAY drop surrounding whitespace to denote precedence — but keep whitespace symmetric:
  - Yes: `x = 2**3 + 5;`, `x = 2*y + 3*z;`, `x = (a+b) * (a-b);`

## Control Structures

- Opening brace on the **same line** as declaration, preceded by a single space.
- Closing brace on its own line at the declaration's indentation level.
- Single space between `if`/`while`/`for` and its `(...)`, and between `(...)` and `{`.
- Braces may be omitted for a single-statement body **only if it fits on one line**:

```solidity
  if (x < 10)
      x += 1;
```

- `else` / `else if` goes on the **same line as the closing brace** (exception to normal brace rules):

```solidity
  if (x < 3) {
      x += 1;
  } else if (x > 7) {
      x -= 1;
  } else {
      x = 5;
  }
```

## Function Declarations

### Short functions

- Opening brace on same line as declaration, preceded by a single space; closing brace aligned with declaration.

```solidity
function increment(uint x) public pure returns (uint) {
    return x + 1;
}
```

- Single-statement short functions MAY be on one line: `function shortFunction() public { doSomething(); }`

### Modifier order

1. Visibility
2. Mutability
3. `virtual`
4. `override`
5. Custom modifiers

```solidity
function balance(uint from) public view override returns (uint) { ... }
```

### Long declarations

- Drop each argument onto its own line (indented one level). Put `)` + opening behavior on their own lines:

```solidity
function thisFunctionHasLotsOfArguments(
    address a,
    address b,
    address c,
    address d,
    address e,
    address f
)
    public
{
    doSomething();
}
```

- If a long declaration has modifiers, put **each modifier on its own line**:

```solidity
function thisFunctionNameIsReallyLong(address x, address y, address z)
    public
    onlyOwner
    priced
    returns (address)
{
    doSomething();
}
```

- Multiline return params follow the same wrapping rules as arguments.

### Inherited constructors with base args

- Drop base constructors onto new lines (like modifiers) when the declaration is long/hard to read:

```solidity
constructor(uint param1, uint param2, uint param3, uint param4, uint param5)
    B(param1)
    C(param2, param3)
    D(param4)
{
    x = param5;
}
```

## Mappings

- No space between `mapping` and its type, including nested mappings.
  - Yes: `mapping(uint => mapping(bool => Data[])) public data;`
  - No: `mapping (uint => mapping (bool => Data[])) public data;`

## Variable Declarations

- No space between an array type and brackets: `uint[] x;` (not `uint [] x;`).

## Other Recommendations

- Use **double quotes** for strings, not single quotes: `str = "foo";`

## Naming Conventions

### Styles defined

- `lowercase`, `UPPERCASE`, `UPPER_CASE_WITH_UNDERSCORES`, `CapWords`, `mixedCase`.
- Initialisms: capitalize all letters in CapWords (`HTTPServerError`). In mixedCase keep first lowercase if at start (`xmlHTTPRequest`).

### Apply

| Element                 | Style                          | Examples                    |
| ----------------------- | ------------------------------ | --------------------------- |
| Contracts & Libraries   | CapWords (must match filename) | `SimpleToken`, `Owned`      |
| Structs                 | CapWords                       | `Position`, `PositionXY`    |
| Events                  | CapWords                       | `Deposit`, `Transfer`       |
| Enums                   | CapWords                       | `TokenGroup`, `Frame`       |
| Functions               | mixedCase                      | `getBalance`, `transfer`    |
| Function arguments      | mixedCase                      | `initialSupply`, `newOwner` |
| Local & state variables | mixedCase                      | `totalSupply`, `isPreSale`  |
| Modifiers               | mixedCase                      | `onlyBy`, `onlyAfter`       |
| Constants               | UPPER_CASE_WITH_UNDERSCORES    | `MAX_BLOCKS`, `TOKEN_NAME`  |

### Naming rules

- **Never** use `l` (el), `O` (oh), or `I` (eye) as single-letter names (confusable with 1/0).
- Library functions operating on a custom struct: the struct is the **first argument**, always named `self`.
- Contract/library name must match its filename (e.g., `Owned` → `Owned.sol`).

### Collision & visibility conventions

- Trailing underscore (`name_`) to avoid collision with an existing state var/function/built-in/reserved name.
- Leading underscore (`_name`) for **non-external** (private/internal) functions and state variables. State vars without explicit visibility default to internal.
  - Rationale: signals intent and forces a review of all call sites when switching a function to/from external — a manual safety check against accidental external exposure. (Avoid blind find-replace-all for this change.)

## NatSpec

- Use NatSpec comments: triple slash `///` or block `/** ... */`, placed directly above declarations/statements.
- Recommended: fully annotate **all public interfaces** (everything in the ABI).
- Common tags: `@title`, `@author`, `@param`, `@dev`, `@return`.

```solidity
/// Store `x`.
/// @param x the new value to store
/// @dev stores the number in the state variable `storedData`
function set(uint x) public {
    storedData = x;
}
```
