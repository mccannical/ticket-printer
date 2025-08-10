try:
    # When executed as a module: python -m src.main
    from .checkin import main  # type: ignore
except ImportError:  # Fallback if run via PYTHONPATH root
    from src.checkin import main  # type: ignore

if __name__ == "__main__":
    main()
