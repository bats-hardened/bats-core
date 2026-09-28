@test "variable is readonly" {
  if (eval "${VARIABLE_TO_REASSIGN?}=changed") 2>/dev/null; then
    return 1
  fi
}
