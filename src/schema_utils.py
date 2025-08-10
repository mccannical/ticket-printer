
import jsonschema

def validate_schema(payload, schema):
	"""
	Validate a payload against a JSON schema. Returns True if valid, raises jsonschema.ValidationError if not.
	"""
	jsonschema.validate(instance=payload, schema=schema)
	return True
