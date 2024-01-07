## ffmpeg-batch.sh Video Encoding with Progress Bar Indicator

A shell script to automate the batch processing of video files using FFmpeg, complemented by a visual progress bar to monitor the encoding process. FFmpeg must be installed prior to running script.

## Features

- **Batch Processing**: Automatically processes all video files in a specified source directory.
- **Progress Bar**: Includes a visual progress indicator for real-time encoding status.
- **CUDA Check**: Checks if FFmpeg has been compiled with CUDA GPU support and adds argument.

## Screenshot
![Terminal Screenshot](/screenshot.png)

## Usage

1. Download or clone the repo:

```terminal
git clone https://github.com/bradsec/ffmpeg-batch.git
```

2. Make excutable:

```terminal
chmod +x ffmpeg-batch.sh
```

3. Run the script with or without command line arguments.

```terminal
# With no additional command line arguments we will be prompted to enter each required option.
./ffmpeg-batch.sh
```

```terminal
# Alternate usage add arguments to command line
./ffmpeg-batch.sh [-src|--src-dir <source_directory>] [-dst|--dst-dir <destination_directory>] [-args|--ffmpeg-args <FFmpeg_arguments>] [-ext|--ffmpeg-file-ext <output_file_extension>]
```

## Acknowledgments

- The progress bar component of this script is adapted from the script '[ffmprog](https://github.com/Rendevior/ffmprog)' by Rendevior. Released under [The Unlicense](https://unlicense.org).
