import jsonschema


def validate_schema(payload, schema):
	"""Validate payload against JSON schema.

	Returns True if valid; raises jsonschema.ValidationError otherwise.
	"""
	jsonschema.validate(instance=payload, schema=schema)
	return True
