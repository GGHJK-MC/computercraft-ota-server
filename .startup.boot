{
  preload = {
    "/packages/lzwfs/startup.lua",
  },
  delay = 0.5,
  menu = {
    {
      prompt = "CraftOS 1.9",
    },
    {
      prompt = "GGHJK OS",
      args = {
        "/sys/boot/opus.lua",
      },
    },
    {
      prompt = "GGHJK OS Shell",
      args = {
        "/sys/boot/opus.lua",
        "/sys/apps/shell.lua",
      },
    },
    {
      prompt = "GGHJK OS Kiosk",
      args = {
        "/sys/boot/kiosk.lua",
      },
    },
    {
      prompt = "GGHJK OS TLCO",
      args = {
        "/sys/boot/tlco.lua",
      },
    },
    {
      prompt = "GGHJK OS Update",
      args = {
        "/recovery/ota.recovery.start",
      },
    },
  },
}
