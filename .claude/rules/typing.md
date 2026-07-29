# Typing discipline

The compiler (Elixir 1.20 whole-program type inference) and Dialyzer both run
in `mix check`, and both are only as useful as the shapes we give them. This
is how the app simulates pyright/pydantic.

- **Structs, never bare maps**, for anything that crosses a function boundary.
  An anonymous map is this language's `any`.
- **`@type t :: %__MODULE__{}` on every schema and struct**, so specs
  elsewhere can name it.
- **`@spec` on every public context function.** These become native type
  signatures when Elixir 1.22 lands, so they are not throwaway.
- **`Ecto.Enum` instead of magic integers or free strings** for closed sets
  (suit, street, action, seat status).
- **Pattern match the expected struct in the function head**
  (`def f(%Table{} = table, ...)`). A runtime type check that costs nothing
  and that the compiler infers from.
- **Money in integer cents**, never float. Chips are integers.
- **`Ecto.embedded_schema` + changeset for external input that has no table**
  (query params, join forms). Validate at the boundary, trust it inward.
- Dialyzer runs with `:unmatched_returns`. When you deliberately discard a
  result, bind it to `_` with a comment saying why. Do not silence it by
  removing the flag.
- Domain values get domain types: a card is `{rank, suit}` behind a `Card.t()`
  type, not a free string. Illegal states should be unrepresentable — prefer
  tagged tuples and closed union types (`@type action :: :fold | :check | ...`)
  over booleans and strings.
