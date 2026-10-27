import os
from server import app

if __name__ == "__main__":
    print("========================================")
    print("GreenGuard AI running on Hugging Face!")
    print("Hardware: 2 vCPU • 16 GB RAM")
    print("========================================")
    # Hugging Face Spaces listens on port 7860
    app.run(host="0.0.0.0", port=7860, debug=False)