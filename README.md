# Ticket Printer Service

A Python service for Raspberry Pi that connects to a backend, registers itself, receives print jobs via message queue, and prints to a thermal printer.

## Structure
- `src/` - Source code
- `config/` - Configuration files
- `logs/` - Log files

## Features
- Registers with backend and sends environment info every 15 minutes
- Subscribes to a message queue (MQTT/AMQP) for print jobs
- Prints to a thermal printer
