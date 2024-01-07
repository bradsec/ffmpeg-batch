#!/bin/sh
# --------------------------------------------------------------------------------
# FFmpeg Batch Encoding with Progress Indicator
#
# Automate video file conversion using FFmpeg, enhanced with a visual progress bar.
# This utility batch processes videos in a designated source directory, converting
# them to a specified format and saving the results in a separate target directory.
# --------------------------------------------------------------------------------

#shellcheck disable=2017

# Create temporary directory for ffmpeg progress information
[ -d "/tmp/ffmpeg_progress" ] || (
    mkdir -p "/tmp/ffmpeg_progress"
    chmod 0700 /tmp /tmp/ffmpeg_progress
)
FFMPEG_PROGRESS_FILE="/tmp/ffmpeg_progress/$$.vstat"

# Trap to handle script interruption
trap 'rm "${FFMPEG_PROGRESS_FILE}" ; restore_terminal ; pkill -9 ffmpeg ; printf "\n\n" ; exit 1' INT HUP
[ -e "${FFMPEG_PROGRESS_FILE}" ] && rm "${FFMPEG_PROGRESS_FILE}"

# Set colors for use in task terminal output functions
term_colors() {
    # Check if stdout is a terminal
    if [ -t 1 ]; then
        RED=$(printf '\033[31m')
        GREEN=$(printf '\033[32m')
        CYAN=$(printf '\033[36m')
        YELLOW=$(printf '\033[33m')
        BLUE=$(printf '\033[34m')
        MAGENTA=$(printf '\033[35m')
        BOLD=$(printf '\033[1m')
        RESET=$(printf '\033[0m')
    else
        RED=""
        GREEN=""
        CYAN=""
        YELLOW=""
        BLUE=""
        MAGENTA=""
        BOLD=""
        RESET=""
    fi
}

# Initialize terminal colors
term_colors


# Restores terminal to its original state
restore_terminal() {
    printf "\033[?25h" # Show Cursor
    printf "\033[0m"   # Normal State of Colors
}

# Cleans up terminal output
sanitize_terminal() {
    printf '%b' "\033[${1}A"
    [ -n "${4}" ] && printf '%b' "\033[${4}B"
    printf "%${2}s" | sed "s_[[:space:]]_\n$(printf "\033[2K\r")_g"
    [ -n "${3}" ] && printf '%b' "\033[${3}A"
}


# Prints info messages in cyan color
info_message() {
    printf "${CYAN}%b${RESET}\n" "${1}"
}

# Prints warning messages in yellow color
warn_message() {
    printf "${YELLOW}%b${RESET}\n" "${1}"
}

# Prints success messages in green color
success_message() {
    printf "${GREEN}%b${RESET}\n" "${1}"
}

# Prints error messages
error_message() {
    [ -n "${1}" ] && printf "${RED}%b${RESET}\n" "${1}" >&2
}

# Terminates script with an error message
terminate_script() {
    error_message "\nError occurred in script."
    [ -n "${2}" ] && error_message "Error Details: ${2}"
    restore_terminal
    [ -e "${FFMPEG_PROGRESS_FILE}" ] && rm "${FFMPEG_PROGRESS_FILE}"
    exit "${1}"
}

# Extracts file information using ffmpeg
get_file_info() {
    [ -z "${1}" ] && terminate_script 127 "No File/URL Returned"
    inf_meta="$(ffprobe -v error -show_entries format=duration -show_streams "${1}" 2>&1)"

    vid_dur_seconds="$(echo "${inf_meta}" | awk -F= '/^duration=/ {print int($2); exit}')"
    vid_fps="$(echo "${inf_meta}" | awk -F= '/^avg_frame_rate=/ {split($2, a, "/"); if (a[2] > 0) print int(a[1]/a[2]); else print 0; exit}')"
    vid_frames=$((vid_fps * vid_dur_seconds))
    vid_res="$(echo "${inf_meta}" | awk -F= '/^width=/ {width=$2} /^height=/ {print width "x" $2; exit}')"
    vid_bitrate="$(echo "${inf_meta}" | awk -F= '/^bit_rate=/ {print int($2/1000) " kb/s"; exit}')"
    vid_codec="$(echo "${inf_meta}" | awk -F= '/^codec_name=/ && !seen {print $2; seen=1; exit}')"
    aud_codec="$(echo "${inf_meta}" | awk -F= '/^codec_name=/ && seen {print $2; exit}')"
    aud_channels="$(echo "${inf_meta}" | awk -F= '/^channels=/ {print $2 " channels"; exit}')"
    aud_samprate="$(echo "${inf_meta}" | awk -F= '/^sample_rate=/ {print $2 " Hz"; exit}')"
    format="$(echo "${inf_meta}" | awk -F= '/^format_name=/ {print $2; exit}')"

    # Convert seconds to hh:mm:ss
    hours=$(($vid_dur_seconds / 3600))
    minutes=$((($vid_dur_seconds % 3600) / 60))
    seconds=$(($vid_dur_seconds % 60))
    vid_dur=$(printf "%02d:%02d:%02d" $hours $minutes $seconds)

    # Diagnostic messages with checks for empty values
    echo ""
    [ -n "${vid_dur}" ] && printf "Video Duration:     %s\n" "${vid_dur}"
    [ -n "${vid_fps}" ] && printf "Video FPS:          %s\n" "${vid_fps}"
    [ -n "${vid_frames}" ] && printf "Video Frames:       %s\n" "${vid_frames}"
    [ -n "${vid_res}" ] && printf "Video Resolution:   %s\n" "${vid_res}"
    [ -n "${vid_bitrate}" ] && printf "Video Bitrate:      %s\n" "${vid_bitrate}"
    [ -n "${vid_codec}" ] && printf "Video Codec:        %s\n" "${vid_codec}"
    [ -n "${aud_codec}" ] && printf "Audio Codec:        %s\n" "${aud_codec}"
    [ -n "${aud_channels}" ] && printf "Audio Channels:     %s\n" "${aud_channels}"
    [ -n "${aud_samprate}" ] && printf "Audio Sample Rate:  %s\n" "${aud_samprate}"
    [ -n "${format}" ] && printf "Format:             %s\n" "${format}"
    echo ""

    if [ -z "${vid_dur_seconds}" ] || [ -z "${vid_fps}" ]; then
        terminate_script 1 "Failed to extract video duration and/or FPS."
    fi
}


# Function to get frame count using ffprobe
get_frame_count() {
    local file="$1"

    if [ -z "${file}" ]; then
        echo "No file provided" >&2
        return 1
    fi

    ffprobe -v error -select_streams v:0 -show_entries stream=nb_frames -of default=noprint_wrappers=1:nokey=1 "${file}"
}

# Handles the progress display
progress_display() {
    local total_frames=$1
    # echo "ffmpeg PID: ${ffmpeg_pid}"
    echo ""
    printf "\033[?25l"
    while [ -e "/proc/${ffmpeg_pid}" ]; do
        if [ -e "${FFMPEG_PROGRESS_FILE}" ]; then
            current_frame="$(grep "frame=" "${FFMPEG_PROGRESS_FILE}" | tail -n 1)" current_frame="${current_frame##*=}"
            current_bitrate="$(grep "bitrate=" "${FFMPEG_PROGRESS_FILE}" | tail -n 1)" current_bitrate="${current_bitrate##*=}"
            if [ -n "${current_frame}" ]; then
                printf '\n%s\n%s\n%s\n%s\033[4A' "Frame:   ${current_frame:-0}/${total_frames}" \
                "Bitrate: ${current_bitrate:-0kbits/s}"
                progress_bar "${current_frame}" "${total_frames}"
                sleep 0.3
            fi
        fi
    done
    restore_terminal
    sanitize_terminal 5 4 4 4
    if wait "${ffmpeg_pid}" >/dev/null; then
        success_message "FFMPEG processing completed."
    else
        terminate_script 1 "FFMPEG processing failed. An error occurred."
    fi
    [ -e "${FFMPEG_PROGRESS_FILE}" ] && rm "${FFMPEG_PROGRESS_FILE}"
}

# Displays a progress bar
progress_bar() {
    local current_frame=$1
    local total_frames=$2

    # Calculate progress percentage
    local prog=$(( current_frame * 100 / total_frames ))

    # Ensure the progress doesn't exceed 100%
    if [ "$prog" -gt 100 ]; then
        prog=100
    fi

    # Calculate the fill length for the progress bar (assuming 40 characters width)
    local fill_length=$(( (prog * 38 / 100) + 2 ))

    local fill=$(printf '%0.s=' $(seq 1 $fill_length))
    local head=""
    if [ "$prog" -lt 100 ]; then
        head=">"
    fi
    local empty=$(printf '%0.s ' $(seq 1 $((40 - fill_length))))

    # Print the progress bar with color
    printf "%s [%s%s%s] %s " "${GREEN}${BOLD}FFMPEG${RESET}" "${CYAN}${fill}" "${head}${RESET}" "$empty" "${GREEN}${prog}%${RESET}"
}

# Checks for required dependencies
dependency_check() {
    for deppack; do
        command -v "${deppack}" >/dev/null || is_err="1"
    done
    [ "${is_err}" = "1" ] && terminate_script 1 "Program \"${deppack}\" is not installed."
}

# Runs ffmpeg command in the background
run_ffmpeg_cmd() {
    local file=$1
    local ffmpeg_args=$2
    local ffmpeg_file_ext=$3
    local partial_output_file=$4

    # Check if ffmpeg has CUDA support
    if ffmpeg -hwaccels 2>&1 | grep -q 'cuda'; then
        hwaccel_cmd="-hwaccel cuda "
    else
        hwaccel_cmd=""
    fi

    ffmpeg -hide_banner -loglevel error -progress "${FFMPEG_PROGRESS_FILE}" -y ${hwaccel_cmd}-i "${file}" ${ffmpeg_args} -f "${ffmpeg_file_ext}" "${partial_output_file}" &
    ffmpeg_pid="${!}"
}

# Default values for command-line options
src_dir_default="src"
dst_dir_default="dst"
ffmpeg_args_default="-c:v libx264 -preset medium -crf 18 -c:a aac -b:a 192k"
ffmpeg_file_ext_default="mp4"

# Function to prompt for missing values
prompt_for_value() {
    local var_name="$1"
    local message="$2"
    local default_value="$3"

    echo -n "$message [$default_value]: "
    read input
    input="${input:-$default_value}" # Use default if Enter is pressed
    eval "$var_name=\"\$input\""
}

# Parse command-line arguments
while [ $# -gt 0 ]; do
    key="$1"

    case $key in
        -src|--src-dir)
            src_dir="$2"
            shift # past argument
            shift # past value
            ;;
        -dst|--dst-dir)
            dst_dir="$2"
            shift # past argument
            shift # past value
            ;;
        -args|--ffmpeg-args)
            ffmpeg_args="$2"
            shift # past argument
            shift # past value
            ;;
        -ext|--ffmpeg-file-ext)
            ffmpeg_file_ext="$2"
            shift # past argument
            shift # past value
            ;;
        *)
            # Unknown option, print usage and exit
            echo "Usage: $0 [-src|--src-dir <source_directory>] [-dst|--dst-dir <destination_directory>] [-args|--ffmpeg-args <FFmpeg_arguments>] [-ext|--ffmpeg-file-ext <output_file_extension>]"
            exit 1
            ;;
    esac
done

main() {
    echo ""
    echo " ##########################################"
    echo " ## FFMPEG Batch Video Processing Script ##"
    echo " ##########################################"
    echo ""
    # Supported file extensions
    supported_extensions="mp4 avi mov mkv"

    # Check for dependencies
    dependency_check "ffmpeg" "ffprobe" "sed" "grep" "awk"

    # Prompt for missing values if not provided
    [ -z "$src_dir" ] && prompt_for_value src_dir "${CYAN}Enter source directory${RESET}" "$src_dir_default"
    [ -z "$dst_dir" ] && prompt_for_value dst_dir "${CYAN}Enter destination directory${RESET}" "$dst_dir_default"
    [ -z "$ffmpeg_args" ] && prompt_for_value ffmpeg_args "${CYAN}Enter FFmpeg arguments${RESET}" "$ffmpeg_args_default"
    [ -z "$ffmpeg_file_ext" ] && prompt_for_value ffmpeg_file_ext "${CYAN}Enter output file extension: mp4 avi mov mkv${RESET}" "$ffmpeg_file_ext_default"

    # Check if src_dir exists
    if [ ! -d "$src_dir" ]; then
        error_message "Source directory \"$src_dir\" does not exist. Please provide a valid source directory."
        exit 1
    fi

    if [ -z "$(ls "$src_dir"/*.{mp4,avi,mov,mkv} 2>/dev/null)" ]; then
        error_message "No supported video files found in the source directory \"$src_dir\"."
        exit 1
    fi

    # Check if dst_videos directory exists, if not create it
    if [ ! -d "$dst_dir" ]; then
        mkdir "$dst_dir"
    fi

    current_file_num=0

    # Iterate over supported file extensions
    for ext in $supported_extensions; do
        for file in "$src_dir"/*.$ext; do
            # Skip if no files found for this extension
            [ -f "$file" ] || continue

            # Increment the current file number
            current_file_num=$((current_file_num + 1))
            total_files=$(ls "$src_dir"/*.$ext | wc -l)

            info_message "\nProcessing file ${current_file_num}/${total_files}:${RESET} $file"

            # Extract the filename without the extension
            filename=$(basename "$file" .$ext)

            # Use manual setting if available, otherwise use input file's extension
            ffmpeg_file_ext="${ffmpeg_file_ext:-$ext}"

            # Construct the output file paths
            partial_output_file="$dst_dir/${filename}_NEW.${ffmpeg_file_ext}.partial"
            final_output_file="$dst_dir/${filename}_NEW.${ffmpeg_file_ext}"

            # Check if the final converted file already exists
            if [ -f "$final_output_file" ]; then
                warn_message "File skipped: ${RESET}$final_output_file exists."
                continue
            fi

            # Extract file information using ffprobe            
            get_file_info "${file}"

            # Extract and store the value of -r from ffmpeg_args as new_fps
            new_fps=""
            if echo "$ffmpeg_args" | grep -q '\-r [0-9]\+'; then
                new_fps=$(echo "$ffmpeg_args" | sed -n 's/.*-r \([0-9]\+\).*/\1/p')
            fi

            # If new_fps is empty, use the existing video fps
            if [ -z "$new_fps" ]; then
                new_fps="$vid_fps"
            fi

            # Calculate the total frames based on new_fps
            total_frames=$((new_fps * vid_dur_seconds))

            # Prepare and run ffmpeg command
            info_message "FFMPEG ARGS: ${RESET}${ffmpeg_args} -f ${ffmpeg_file_ext}"
            run_ffmpeg_cmd "${file}" "${ffmpeg_args}" "${ffmpeg_file_ext}" "${partial_output_file}"
            progress_display "${total_frames}"

            # Rename partial file to final file name upon successful completion
            if [ $? -eq 0 ]; then
                mv "$partial_output_file" "$final_output_file"
                success_message "\nOutput file:${RESET} $final_output_file"
            else
                error_message "Conversion failed for $filename"
            fi
        done
    done
}

main "$@"


