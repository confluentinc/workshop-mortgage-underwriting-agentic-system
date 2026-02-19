## Zapier Remote MCP Server Setup

Create a Zapier MCP server for tool calling:

<a id="step-1"></a>
### 1. Create free Zapier Account

Sign up for a free account at [zapier.com](https://zapier.com/sign-up) and verify your email.

<a id="step-2"></a>
### 2. Create MCP Server

Visit [mcp.zapier.com](https://mcp.zapier.com/mcp/servers), choose **"Other"** as MCP Client, and create your server.

<img src="./zapier-screenshots/3.png" alt="Create MCP Server" width="50%" />

<a id="step-3"></a>
### 3. Add Tools

Add the following tool to your MCP server:

- **`Gmail: Send Email`** tool (authenticate via SSO).

    <img src="./zapier-screenshots/4.png" alt="Add Tools" width="50%" />

<a id="step-4"></a>
### 4. Get Zapier Token

> **Note:** SSE endpoints are now deprecated. Use Streamable HTTP instead.

* Click **Connect** Tab to open the connection credentials dialog.
* Select **Rotate token**. Rotating the token will invalidate the existing connection token, so any clients using the old token must be updated. Confirm by clicking **Rotate token** again.
* Select **Authorization header** and copy the token from the **Token** field. You will need this as the `zapier_token` parameter when deploying the lab.

    <img src="./zapier-screenshots/7.png" alt="Streamable HTTP Token" width="50%" />

The endpoint `https://mcp.zapier.com/api/v1/connect` is the same for all Zapier MCP servers - you only need to copy the token. Copy it somewhere safe.

## Checklist

- [ ] Created MCP server and chose "Other" as the MCP client ([step 2](#step-2))
- [ ] Added **`Gmail: Send Email`** tool ([step 3](#step-3))
- [ ] Copied the token somewhere safe, to enter it later during deployment ([step 4](#step-4))

## Navigation

- **← Back to Overview**: [Main README](../README.md)
