variable "cloud_id" {
  type = string
}

variable "folder_id" {
  type = string
}

variable "bucket_name" {
  type        = string
  description = "Имя бакета БЕЗ префикса. Итоговое имя: vvot<NN>-<bucket_name>"

  validation {
    condition     = !startswith(var.bucket_name, "vvot")
    error_message = "Передавай имя без префикса vvot<NN>- — он добавляется автоматически из locals."
  }
}