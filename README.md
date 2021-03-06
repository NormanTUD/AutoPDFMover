# AutoPDFMover

This script allows OCR'ing documents and moving them according to information in the document.

I created it to split a large PDF and move the seperated pages according to the information in the PDFs.

It looks for things like "Herr Vorname mittlerer Name Nachname" and moves them to `done/Herr Vorname mittlerer Name Nachname.pdf`. Also works
with `Frau Soundso Nachname`.

If a file by the name already exists, "-0" is automatically appended. If this already exists, "-1" will be appended and so on.

Files whose names cannot be determined will be moved to the `manual` folder.

# Dependencies

You need to install Tesseract Version 5.0.0-alpha (this can be done automatically with https://github.com/NormanTUD/UsefulFreeHomeServer),
you also need GhostScript, ImageMagick and pdftk.

# How to use it

Create a folder called `todo` and put one or many PDFs in that folder. Then run

> perl parse.pl --todo=/path/to/TODO --tmp=/path/to/TMP --manual=/path/to/MANUAL --done=/path/to/DONE --crop=4000x240+260+2200

If no paths are specified, it looks in the same folder where the script itself is in.

The `--crop` parameter can be left empty, but this is not recommended. It crops the image of the PDF before OCR, so that

* OCR is much faster

* OCR recognition is much more reliable

The crop parameter gets passed directly to ImageMagick when set. It is specified this way:

`${WIDTH}x${HEIGHT}+{YSTART}+{XSTART}`

and should be set according to your document.

# How to use the other scripts

Assuming you try to get German-like names, you can use the `check.pl` in whatever folder you are in. It will check for names that the script
may have gotten wrongly. Use it with `perl check.pl`.

You can also use the `missing.pl` to get documents that are missing. 

Both of these will not yet work with --todo, --tmp and --done and assume that you did not use any special paths.
