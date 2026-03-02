resource "aws_bedrockagentcore_memory" "this" {
  name                  = var.memory_name
  description           = var.description
  event_expiry_duration = var.event_expiry_days
}

resource "aws_bedrockagentcore_memory_strategy" "this" {
  for_each = { for idx, strategy in var.strategies : idx => strategy }

  name        = each.value.name
  memory_id   = aws_bedrockagentcore_memory.this.id
  type        = each.value.type
  namespaces  = each.value.namespaces
  description = each.value.description

  dynamic "configuration" {
    for_each = each.value.configuration != null ? [each.value.configuration] : []
    content {
      type = configuration.value.type

      dynamic "consolidation" {
        for_each = configuration.value.consolidation != null ? [configuration.value.consolidation] : []
        content {
          append_to_prompt = consolidation.value.append_to_prompt
          model_id         = consolidation.value.model_id
        }
      }

      dynamic "extraction" {
        for_each = configuration.value.extraction != null ? [configuration.value.extraction] : []
        content {
          append_to_prompt = extraction.value.append_to_prompt
          model_id         = extraction.value.model_id
        }
      }
    }
  }
}
