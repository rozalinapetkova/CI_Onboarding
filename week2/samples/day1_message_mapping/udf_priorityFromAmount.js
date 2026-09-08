// UDF — priorityFromAmount
// Execution type: Single Value
// Argument: amount (string from the source queue)
// Returns: "HIGH" | "MEDIUM" | "LOW"
//
// Paste this verbatim into the UDF editor. CI's UDF runtime is Nashorn-class
// JavaScript — ES5 syntax only. No `let`, no arrow functions, no template literals.

function priorityFromAmount(amount) {
    var n = parseFloat(amount);
    if (isNaN(n)) return "LOW";
    if (n >= 100000) return "HIGH";
    if (n >= 10000)  return "MEDIUM";
    return "LOW";
}
