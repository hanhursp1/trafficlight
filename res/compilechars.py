from PIL import Image
import os.path

current_dir : str = os.path.dirname(os.path.realpath(__file__))

# Iterate from 0 to 8
for i in range(8):
  path : str = current_dir + "/" + str(i)
  # Check if the png file exists. If not, then move on.
  if not os.path.isfile(path + ".png"):
    continue

  print("Compiling character file:", path + ".char")

  # Open the image and convert it to 1-bit
  im : Image.Image = Image.open(path + ".png").convert('1', None, Image.Dither.NONE)

  # Check to make sure the sprite is 5x8. If not, then continue
  if im.size != (5, 8):
    print("Sprite must be 5x8")
    continue

  # Output byte array.
  output : bytearray = bytearray(8)

  # Iterate over every pixel in the image. If it's more than half white
  # then set the corresponding bit
  for y in range(im.size[1]):
    for x in range(im.size[0]):
      pix: int = 1 if im.getpixel((x, y)) > 127 else 0
      output[y] = (output[y]<<1) | pix

  # Write the output to the corresponding character file
  with open(path + ".char", "wb") as outFile:
    outFile.write(output)