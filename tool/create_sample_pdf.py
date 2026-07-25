from pathlib import Path

from reportlab.lib.colors import HexColor
from reportlab.lib.pagesizes import A4
from reportlab.pdfgen import canvas


output = Path(__file__).resolve().parents[1] / "output" / "pdf" / "papertrail-sample.pdf"
output.parent.mkdir(parents=True, exist_ok=True)

width, height = A4
pdf = canvas.Canvas(str(output), pagesize=A4)
pdf.setTitle("Welcome to Papertrail PDF")

purple = HexColor("#5B5BD6")
ink = HexColor("#20202A")
muted = HexColor("#6B6B78")

pdf.setFillColor(purple)
pdf.rect(0, height - 190, width, 190, fill=1, stroke=0)
pdf.setFillColorRGB(1, 1, 1)
pdf.setFont("Helvetica-Bold", 30)
pdf.drawString(54, height - 92, "Welcome to Papertrail PDF")
pdf.setFont("Helvetica", 14)
pdf.drawString(54, height - 124, "A private, offline-first place for your documents.")

pdf.setFillColor(ink)
pdf.setFont("Helvetica-Bold", 20)
pdf.drawString(54, height - 248, "Your sample document")
pdf.setFillColor(muted)
pdf.setFont("Helvetica", 12)
lines = [
    "This PDF was created so you can test the reader in the Android emulator.",
    "Try pinch-to-zoom, page navigation, text selection, and dark mode.",
    "When you close the document, Papertrail remembers your reading position.",
]
for index, line in enumerate(lines):
    pdf.drawString(54, height - 282 - index * 24, line)

cards = [
    ("1", "Open", "Choose a PDF from your device."),
    ("2", "Read", "Zoom and move through pages smoothly."),
    ("3", "Resume", "Continue where you stopped."),
]
for index, (number, title, body) in enumerate(cards):
    y = height - 410 - index * 94
    pdf.setFillColor(HexColor("#EEEEFF"))
    pdf.roundRect(54, y, 46, 46, 12, fill=1, stroke=0)
    pdf.setFillColor(purple)
    pdf.setFont("Helvetica-Bold", 16)
    pdf.drawCentredString(77, y + 16, number)
    pdf.setFillColor(ink)
    pdf.setFont("Helvetica-Bold", 14)
    pdf.drawString(118, y + 28, title)
    pdf.setFillColor(muted)
    pdf.setFont("Helvetica", 11)
    pdf.drawString(118, y + 10, body)

pdf.setFillColor(muted)
pdf.setFont("Helvetica", 9)
pdf.drawString(54, 42, "Papertrail PDF - Sample document")
pdf.drawRightString(width - 54, 42, "Page 1 of 1")
pdf.save()

print(output)
