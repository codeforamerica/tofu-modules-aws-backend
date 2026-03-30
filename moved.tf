moved {
  from = aws_dynamodb_table.tfstate_lock
  to   = aws_dynamodb_table.tfstate_lock["this"]
}
