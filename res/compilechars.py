from PIL import Image
import os.path


for i in range(8):
  path: str = "res/" + str(i)
  if not os.path.isfile(path + ".png"):
    continue

  print("Compiling character file:", path + ".char")

  im : Image.Image = Image.open(path + ".png").convert('1', None, Image.Dither.NONE)

  if im.size != (5, 8):
    print("Image must be 5x8")
    exit(-1)

  output : bytearray = bytearray(8)

  for y in range(im.size[1]):
    for x in range(im.size[0]):
      pix: int = 1 if im.getpixel((x, y)) > 127 else 0
      output[y] = (output[y]<<1) | pix

  with open(path + ".char", "wb") as outFile:
    outFile.write(output)