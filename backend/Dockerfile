# Use a slim Python 3.11 base image
FROM python:3.11-slim

# Set environment variables to optimize Python for production
# PYTHONUNBUFFERED=1 ensures that logs are sent straight to the terminal without buffering
# PYTHONDONTWRITEBYTECODE=1 prevents Python from writing .pyc files
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# Set the working directory to /app
WORKDIR /app

# Copy requirements file first for better caching
COPY requirements.txt .

# Install dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy the rest of the backend code
COPY . .

# Use functions-framework as the entry point
# --target specifies the function to execute
# --port defaults to 8080 for Cloud Run
CMD functions-framework --target=fetch_bq_epitopes --port=$PORT
