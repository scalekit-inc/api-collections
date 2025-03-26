# Scalekit API Postman Collection

This directory contains Postman collection and environment files to help you explore and test Scalekit APIs.

## Contents

- `scalekit-api-endpoints.postman_collection.json` - Collection of API endpoints for Scalekit
- `scalekit-api-endpoints.postman_environment.json` - Environment variables for the collection

## Getting Started

### If you already use Postman

1. **Import the Collection**:

   - Open Postman
   - Click on "Import" in the top left corner
   - Drag and drop the `scalekit-api-endpoints.postman_collection.json` file or browse to select it
   - Click "Import" to confirm

2. **Import the Environment**:

   - Click on "Import" again
   - Drag and drop the `scalekit-api-endpoints.postman_environment.json` file or browse to select it
   - Click "Import" to confirm

3. **Set up the Environment**:

   - Click on the environment dropdown in the top right corner of Postman
   - Select "Scalekit API Sandbox"
   - Click on the eye icon next to the environment dropdown
   - Update the following variables with your own values:
     - `client_id` - Your Scalekit client ID
     - `client_secret` - Your Scalekit client secret
     - `env_url` - Your Scalekit environment URL
     - Other variables as needed for your specific use case

4. **Use the Collection**:
   - Start with the "Auth to get Access Token" request in the "Getting Started" folder
   - This will automatically set the `access_token` variable for subsequent requests
   - Explore other API endpoints in the collection

### If you don't have Postman

1. **Download and Install Postman**:

   - Visit [postman.com/downloads](https://www.postman.com/downloads/)
   - Download the version for your operating system
   - Install and launch Postman

2. **Create an Account or Skip**:

   - You can create a Postman account or skip and use it without an account

3. **Follow the steps above** to import the collection and environment

## Notes

- The collection includes pre-request scripts and test scripts that help manage authentication tokens
- Make sure to update all environment variables with your actual Scalekit credentials
- Some requests may require additional configuration based on your specific setup
