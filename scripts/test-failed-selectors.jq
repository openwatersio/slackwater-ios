.. | objects
| select(.nodeType == "Unit test bundle" or .nodeType == "UI test bundle")
| .name as $target
| .. | objects
| select(.nodeType == "Test Case" and .result == "Failed")
| $target + "/" + (.nodeIdentifier | sub("\\(\\)$"; ""))
