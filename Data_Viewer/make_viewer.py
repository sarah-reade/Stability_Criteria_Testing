#!/usr/bin/env python3

import json
import html
import sys
from pathlib import Path

if len(sys.argv) != 2:
    print("Usage: python make_viewer.py <results_folder>")
    sys.exit(1)

root = Path(sys.argv[1]).resolve()

folders = []

for folder in sorted([d for d in root.iterdir() if d.is_dir()]):

    metadata_file = folder / "metaData.txt"

    metaData = ""
    if metadata_file.exists():
        metaData = metadata_file.read_text(errors="ignore")

    svgs = sorted(folder.glob("*.svg"))

    folders.append({
        "name": folder.name,
        "metaData": metaData,
        "figures": [str(f.relative_to(root)).replace("\\", "/") for f in svgs]
    })

data = json.dumps(folders)

html_text = f"""<!DOCTYPE html>
<html>
<head>

<meta charset="utf-8">

<title>Experiment Viewer</title>

<style>

body {{
    margin:0;
    font-family:Arial,Helvetica,sans-serif;
    background:#f4f4f4;
}}

header {{
    position:sticky;
    top:0;
    background:#2d2d2d;
    color:white;
    display:flex;
    justify-content:space-between;
    align-items:center;
    padding:15px;
    font-size:22px;
    z-index:100;
}}

button {{
    font-size:18px;
    padding:10px 18px;
    cursor:pointer;
}}

.container {{
    max-width:1200px;
    margin:auto;
    padding:20px;
}}

.card {{
    background:white;
    border-radius:10px;
    margin-bottom:30px;
    box-shadow:0 2px 8px rgba(0,0,0,.15);
    overflow:hidden;
}}

.card h2 {{
    margin:0;
    padding:15px;
    background:#e9e9e9;
}}

pre {{
    margin:0;
    padding:20px;
    white-space:pre-wrap;
    font-family:Consolas,monospace;
    overflow-x:auto;
}}

.figure {{
    padding:20px;
    text-align:center;
}}

.figure img {{
    max-width:100%;
    max-height:900px;
    border:1px solid #ddd;
}}

.footer {{
    text-align:center;
    color:#777;
    margin:30px;
}}

.zoom-container {{
    width: 100%;
    height: 900px;
    overflow: hidden;
    border: 1px solid #ddd;
    cursor: grab;
    display: flex;
    justify-content: center;
    align-items: center;
    background: white;
}}

.zoom-container:active {{
    cursor: grabbing;
}}

.zoomable {{
    transform-origin: center center;
    user-select: none;
    -webkit-user-drag: none;
    max-width: none;
    max-height: none;
}}

</style>

</head>

<body>

<header>

<button onclick="previous()">◀ Previous</button>

<div id="title"></div>

<button onclick="next()">Next ▶</button>

</header>

<div class="container" id="content"></div>

<script>

const folders = {data};

let current = 0;

function escapeHTML(text){{
    return text
      .replace(/&/g,"&amp;")
      .replace(/</g,"&lt;")
      .replace(/>/g,"&gt;");
}}

function render(){{

    let f = folders[current];

    document.getElementById("title").innerHTML =
        f.name + " (" + (current+1) + "/" + folders.length + ")";

    let html = "";

    html += `
    <div class="card">
        <h2>Metadata</h2>
        <pre>${{escapeHTML(f.metaData)}}</pre>
    </div>
    `;

    for(let fig of f.figures){{
        let name = fig.split("/").pop();

        html += `
        <div class="card">

            <h2>${{name}}</h2>

            <div class="figure">

                <div class="zoom-container">
                    <img class="zoomable" src="${{fig}}">
                </div>

            </div>

        </div>
        `;
    }}

    document.getElementById("content").innerHTML = html;
    
    document.querySelectorAll(".zoom-container").forEach(setupZoom);

}}

function setupZoom(container){{

    const img = container.querySelector("img");

    let scale = 1;
    let x = 0;
    let y = 0;

    let dragging = false;
    let lastX = 0;
    let lastY = 0;

    function update(){{
        img.style.transform =
            `translate(${{x}}px, ${{y}}px) scale(${{scale}})`;
    }}

    container.addEventListener("wheel", e => {{
        e.preventDefault();

        const factor = e.deltaY < 0 ? 1.1 : 0.9;
        scale *= factor;

        scale = Math.max(0.2, Math.min(scale, 20));

        update();
    }});

    container.addEventListener("mousedown", e => {{
        dragging = true;
        lastX = e.clientX;
        lastY = e.clientY;
    }});

    window.addEventListener("mouseup", () => {{
        dragging = false;
    }});

    window.addEventListener("mousemove", e => {{

        if(!dragging) return;

        x += e.clientX - lastX;
        y += e.clientY - lastY;

        lastX = e.clientX;
        lastY = e.clientY;

        update();
    }});

    container.addEventListener("dblclick", () => {{
        scale = 1;
        x = 0;
        y = 0;
        update();
    }});

    update();
}}

function previous(){{
    if(current>0){{
        current--;
        render();
    }}
}}

function next(){{
    if(current<folders.length-1){{
        current++;
        render();
    }}
}}

document.addEventListener("keydown",function(e){{
    if(e.key==="ArrowRight") next();
    if(e.key==="ArrowLeft") previous();
}});

render();

</script>

</body>
</html>
"""

(root / "viewer.html").write_text(html_text, encoding="utf8")

print(f"Wrote {root/'viewer.html'}")