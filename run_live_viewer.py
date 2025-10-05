#!/usr/bin/env python3
"""
Standalone script to run the Bedrock-AgentCore Browser Live Viewer.
This shows how to use the interactive_tools modules.
"""

import argparse
import time
from pathlib import Path

from rich.console import Console
from rich.panel import Panel
from bedrock_agentcore.tools.browser_client import BrowserClient
from browser_viewer import BrowserViewerServer

console = Console()

def main():
    """Run the browser live viewer with display sizing."""
    # Parse command line arguments
    parser = argparse.ArgumentParser(description="Bedrock-AgentCore Browser Live Viewer")
    parser.add_argument("--browser_session_id", help="Browser session ID to view")
    parser.add_argument("--port", type=int, default=8000, help="Server port (default: 8000)")
    args = parser.parse_args()

    console.print(Panel(
        "[bold cyan]Bedrock-AgentCore Browser Live Viewer[/bold cyan]\n\n"
        "This demonstrates:\n"
        "• Live browser viewing with DCV\n"
        "• Configurable display sizes (not limited to 900×800)\n"
        "• Proper display layout callbacks\n\n"
        "[yellow]Note: Requires Amazon DCV SDK files[/yellow]",
        title="Browser Live Viewer",
        border_style="blue"
    ))

    try:
        console.print(f"\n[cyan]Using browser session: {args.browser_session_id}[/cyan]")

        # Start viewer server
        console.print(f"\n[cyan]Starting viewer server on port {args.port}...[/cyan]")
        viewer = BrowserViewerServer(port=args.port)
        viewer_url = viewer.start(browser_session_id=args.browser_session_id, open_browser=False)

        console.print(f"\n[bold green]Viewer URL:[/bold green]")
        console.print(f"{viewer_url}")

        # Show features
        console.print("\n[bold green]Viewer Features:[/bold green]")
        console.print("• Default display: 1600×900 (configured via displayLayout callback)")
        console.print("• Size options: 720p, 900p, 1080p, 1440p")
        console.print("• Real-time display updates")

        console.print("\n[yellow]Press Ctrl+C to stop[/yellow]")

        # Keep running
        while True:
            time.sleep(1)

    except KeyboardInterrupt:
        console.print("\n\n[yellow]Shutting down...[/yellow]")
    except Exception as e:
        console.print(f"\n[red]Error: {e}[/red]")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    main()
