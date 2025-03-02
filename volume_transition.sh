#!/bin/bash

# Get the directory where the script is located (with better error handling)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
echo "Script directory: $SCRIPT_DIR"

# Configuration
BEARER="Authorization: Bearer ABC123"
URL="http://192.168.1.4:8123"

TRANSITIONS_FILE="${SCRIPT_DIR}/transitions.json"
STEP_SIZE=0.01
SLEEP_INTERVAL=4
MAX_RUNTIME=180  # Maximum runtime in seconds (3 minutes)

# Debug information
echo "Current user: $(whoami)"
echo "Current permissions: $(ls -l $SCRIPT_DIR)"
echo "Attempting to create/access: $TRANSITIONS_FILE"

# Make sure the script directory is writable
if [ ! -w "$SCRIPT_DIR" ]; then
    echo "Error: Script directory is not writable: $SCRIPT_DIR"
    chmod 777 "$SCRIPT_DIR" 2>/dev/null || {
        echo "Failed to set permissions on script directory"
        exit 1
    }
fi

# Initialize transitions file if it doesn't exist
if [ ! -f "$TRANSITIONS_FILE" ]; then
    echo "Creating new transitions file..."
    touch "$TRANSITIONS_FILE" 2>/dev/null || {
        echo "Failed to create transitions file, trying with sudo..."
        sudo touch "$TRANSITIONS_FILE" 2>/dev/null
    }
    
    if [ -f "$TRANSITIONS_FILE" ]; then
        echo '{}' > "$TRANSITIONS_FILE"
        # Ensure file is readable/writable by all users
        chmod 666 "$TRANSITIONS_FILE" 2>/dev/null || {
            echo "Failed to set permissions on transitions file"
            sudo chmod 666 "$TRANSITIONS_FILE" 2>/dev/null
        }
        echo "Transitions file created successfully"
    else
        echo "Error: Could not create transitions file"
        exit 1
    fi
else
    # Ensure existing file has correct permissions
    chmod 666 "$TRANSITIONS_FILE" 2>/dev/null || {
        echo "Failed to set permissions on existing transitions file"
        sudo chmod 666 "$TRANSITIONS_FILE" 2>/dev/null
    }
    echo "Using existing transitions file"
fi

# Verify the file is readable and writable
if [ ! -r "$TRANSITIONS_FILE" ] || [ ! -w "$TRANSITIONS_FILE" ]; then
    echo "Error: transitions.json is not readable or writable"
    echo "Please check permissions: $TRANSITIONS_FILE"
    exit 1
fi

# After the SCRIPT_DIR definition, add this debug function
debug_json_file() {
    echo "=== JSON File Debug ==="
    echo "JSON file path: $TRANSITIONS_FILE"
    if [ -f "$TRANSITIONS_FILE" ]; then
        echo "File exists"
        echo "Permissions: $(ls -l $TRANSITIONS_FILE)"
        echo "Content:"
        cat "$TRANSITIONS_FILE"
    else
        echo "File does not exist"
    fi
    echo "===================="
}

# Function to get current volume
get_current_volume() {
    local speaker=$1
    local response=$(curl -s -X GET \
        -H "$BEARER" \
        -H "Content-Type: application/json" \
        "$URL/api/states/media_player.$speaker")
    
    # Only get the volume level without all the extra info
    volume=$(echo "$response" | /usr/bin/jq -r '.attributes.volume_level // 0' 2>/dev/null)
    printf "%.2f" $volume  # Format to 2 decimal places
}

# Function to get current state
get_current_state() {
    local speaker=$1
    local response=$(curl -s -X GET \
        -H "$BEARER" \
        -H "Content-Type: application/json" \
        "$URL/api/states/media_player.$speaker")
    
    # Only get the state without all the extra info
    state=$(echo "$response" | /usr/bin/jq -r '.state // "unknown"' 2>/dev/null)
    echo "$state"
}

# Function to set volume
set_volume() {
    local speaker=$1
    local volume=$2
    
    # Round to 2 decimal places
    volume=$(printf "%.2f" $volume)
    
    curl -s -X POST \
        -H "$BEARER" \
        -H "Content-Type: application/json" \
        -d "{\"entity_id\": \"media_player.$speaker\", \"volume_level\": $volume}" \
        "$URL/api/services/media_player/volume_set" >/dev/null 2>&1
}

# Function to kill existing transition
kill_transition() {
    local speaker=$1
    local pid_file="${SCRIPT_DIR}/volume_transition_${speaker}.pid"
    local log_file="${SCRIPT_DIR}/volume_transition_${speaker}.log"
    local current_pid=$$
    
    if [ -f "$pid_file" ]; then
        local old_pid=$(cat "$pid_file")
        
        # Don't kill ourselves
        if [ "$old_pid" = "$current_pid" ]; then
            return 0
        fi
        
        echo "Killing previous transition for $speaker (PID: $old_pid)"
        
        # First try graceful kill
        kill $old_pid 2>/dev/null || true
        
        # Wait for process to die
        for i in {1..10}; do
            if ! kill -0 $old_pid 2>/dev/null; then
                break
            fi
            sleep 0.1
        done
        
        # Force kill if still running
        if kill -0 $old_pid 2>/dev/null; then
            kill -9 $old_pid 2>/dev/null || true
            sleep 0.1
        fi
        
        # Always clean up files
        rm -f "$pid_file"
        rm -f "$log_file"
        
        # Clean up transitions file
        /usr/bin/jq --arg speaker "$speaker" 'del(.[$speaker])' \
            "$TRANSITIONS_FILE" > "${TRANSITIONS_FILE}.tmp" && \
        mv "${TRANSITIONS_FILE}.tmp" "$TRANSITIONS_FILE"
    fi
}

# Add near the top of the script after the configuration
should_exit() {
    local speaker=$1
    local pid_file="${SCRIPT_DIR}/volume_transition_${speaker}.pid"
    
    # Check if our PID matches the one in the PID file
    if [ -f "$pid_file" ]; then
        local file_pid=$(cat "$pid_file")
        if [ "$file_pid" != "$$" ]; then
            return 0  # Should exit
        fi
    else
        return 0  # Should exit
    fi
    return 1  # Should continue
}

# Function to handle volume transition
handle_transition() {
    local speaker=$1
    local target=$2
    local pid_file="${SCRIPT_DIR}/volume_transition_${speaker}.pid"
    local log_file="${SCRIPT_DIR}/volume_transition_${speaker}.log"
    
    # Check if speaker is playing
    local state=$(get_current_state "$speaker")
    if [ "$state" != "playing" ]; then
        echo "Speaker is not playing, cancelling transition"
        return 1
    fi
    
    # Kill existing transition
    kill_transition "$speaker"
    
    # Short wait to ensure cleanup is complete
    sleep 0.5
    
    # Get current volume
    local current=$(get_current_volume "$speaker")
    if [ -z "$current" ]; then
        echo "Error: Could not get current volume for $speaker"
        exit 1
    fi
    
    echo "Before JSON update:"
    debug_json_file
    
    # Start new transition in background
    (
        # Store our PID immediately
        echo $$ > "$pid_file"
        
        # Update transitions file with new transition data
        /usr/bin/jq --arg speaker "$speaker" \
           --arg pid "$$" \
           --arg current "$current" \
           --arg target "$target" \
           '.[$speaker] = {"pid": $pid, "current": $current, "target": $target}' \
           "$TRANSITIONS_FILE" > "${TRANSITIONS_FILE}.tmp" && \
        mv "${TRANSITIONS_FILE}.tmp" "$TRANSITIONS_FILE"
        
        # Record start time
        start_time=$(date +%s)
        stuck_count=0
        
        echo "=== Starting Volume Transition ===" > "$log_file"
        echo "Speaker: $speaker" >> "$log_file"
        echo "Current Volume: $current" >> "$log_file"
        echo "Target Volume: $target" >> "$log_file"
        echo "Process PID: $$" >> "$log_file"
        
        while true; do
            # Verify we still own this transition
            if [ ! -f "$pid_file" ] || [ "$(cat "$pid_file" 2>/dev/null)" != "$$" ]; then
                echo "Transition cancelled" >> "$log_file"
                rm -f "$log_file"
                exit 0
            fi

            # **Check if the speaker is still playing**
            local current_state=$(get_current_state "$speaker")
            if [ "$current_state" != "playing" ]; then
                echo "Speaker stopped playing, cancelling transition" >> "$log_file"
                # Clean up transitions file
                /usr/bin/jq --arg speaker "$speaker" 'del(.[$speaker])' \
                    "$TRANSITIONS_FILE" > "${TRANSITIONS_FILE}.tmp" && \
                mv "${TRANSITIONS_FILE}.tmp" "$TRANSITIONS_FILE"

                rm -f "$pid_file"
                rm -f "$log_file"
                exit 0
            fi

            # Get fresh current volume
            current=$(get_current_volume "$speaker")
            
            # Check if we've exceeded maximum runtime
            current_time=$(date +%s)
            runtime=$((current_time - start_time))
            
            if [ $runtime -gt $MAX_RUNTIME ]; then
                echo "ERROR: Transition timed out after ${MAX_RUNTIME} seconds" >> "$log_file"
                
                # Clean up transitions file
                /usr/bin/jq --arg speaker "$speaker" 'del(.[$speaker])' \
                    "$TRANSITIONS_FILE" > "${TRANSITIONS_FILE}.tmp" && \
                mv "${TRANSITIONS_FILE}.tmp" "$TRANSITIONS_FILE"
                
                rm -f "$pid_file"
                rm -f "$log_file"
                exit 1
            fi
            
            # Calculate new volume
            if (( $(echo "$current < $target" | bc -l) )); then
                new_volume=$(echo "$current + $STEP_SIZE" | bc -l)
                if (( $(echo "$new_volume > $target" | bc -l) )); then
                    new_volume=$target
                fi
            else
                new_volume=$(echo "$current - $STEP_SIZE" | bc -l)
                if (( $(echo "$new_volume < $target" | bc -l) )); then
                    new_volume=$target
                fi
            fi
            
            # Raspberry Pi Volume Adjustment
            if [ "$speaker" = "raspberry_pi" ] || [ "$speaker" = "raspberry_pi_zero" ]; then
                # Convert to percentage for easier comparison (0-100 scale)
                volume_pct=$(echo "$new_volume * 100" | bc -l)
                
                # Going up
                if (( $(echo "$current < $target" | bc -l) )); then
                    if (( $(echo "$volume_pct > 28 && $volume_pct < 32" | bc -l) )); then
                        new_volume=0.32  # Jump to 32%
                        echo "Jump up! Volume set to 32%" >> "$log_file"
                    elif (( $(echo "$volume_pct > 56 && $volume_pct < 59" | bc -l) )); then
                        new_volume=0.59  # Jump to 59%
                        echo "Jump up! Volume set to 59%" >> "$log_file"
                    fi
                # Going down
                else
                    if (( $(echo "$volume_pct > 28 && $volume_pct < 32" | bc -l) )); then
                        new_volume=0.28  # Jump to 28%
                        echo "Jump down! Volume set to 28%" >> "$log_file"
                    elif (( $(echo "$volume_pct > 56 && $volume_pct < 59" | bc -l) )); then
                        new_volume=0.56  # Jump to 56%
                        echo "Jump down! Volume set to 56%" >> "$log_file"
                    fi
                fi
            fi
            
            printf "Volume: %.2f → %.2f (Runtime: ${runtime}s)\n" $current $new_volume >> "$log_file"
            set_volume "$speaker" "$new_volume"
            
            # Check if we're stuck
            if (( $(echo "($current - $new_volume) < 0.001 && ($current - $new_volume) > -0.001" | bc -l) )); then
                stuck_count=$((stuck_count + 1))
                if [ $stuck_count -gt 5 ]; then
                    echo "ERROR: Volume transition stuck, aborting" >> "$log_file"
                    
                    # Clean up transitions file
                    /usr/bin/jq --arg speaker "$speaker" 'del(.[$speaker])' \
                        "$TRANSITIONS_FILE" > "${TRANSITIONS_FILE}.tmp" && \
                    mv "${TRANSITIONS_FILE}.tmp" "$TRANSITIONS_FILE"
                    
                    rm -f "$pid_file"
                    rm -f "$log_file"
                    exit 1
                fi
            else
                stuck_count=0
            fi
            
            if (( $(echo "$new_volume == $target" | bc -l) )); then
                echo "Target volume reached: $target (Total runtime: ${runtime}s)" >> "$log_file"
                
                # Clean up transitions file
                        /usr/bin/jq --arg speaker "$speaker" 'del(.[$speaker])' \
                            "$TRANSITIONS_FILE" > "${TRANSITIONS_FILE}.tmp" && \
                        mv "${TRANSITIONS_FILE}.tmp" "$TRANSITIONS_FILE"
                        
                        rm -f "$pid_file"
                        rm -f "$log_file"
                        exit 0
                    fi
                    
                    sleep $SLEEP_INTERVAL
                done
                ) &
                    
                    # Get the PID of the background process
                    local bg_pid=$!
                    
                    # Wait for process to start
                    for i in {1..10}; do
                        if [ -f "$pid_file" ] && [ "$(cat "$pid_file")" = "$bg_pid" ]; then
                            break
                        fi
                        sleep 0.1
                    done
                    
                    # Verify process started successfully
                    if [ ! -f "$pid_file" ] || [ "$(cat "$pid_file")" != "$bg_pid" ]; then
                        echo "Error: Could not start volume transition process"
                        exit 1
                    fi
                }

                # Main script
                if [ $# -ne 2 ]; then
                    echo "Usage: $0 <speaker> <target_volume>"
                    exit 1
                fi

                speaker=$1
                target_volume=$2

                # Validate speaker
                if [ -z "$speaker" ]; then
                    echo "Error: Speaker cannot be empty"
                    exit 1
                fi

                # Validate target volume
                if ! [[ $target_volume =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                    echo "Error: Target volume must be a number"
                    exit 1
                fi

                if (( $(echo "$target_volume < 0" | bc -l) )) || (( $(echo "$target_volume > 1" | bc -l) )); then
                    echo "Error: Target volume must be between 0 and 1"
                    exit 1
                fi

                # Start volume transition
                handle_transition "$speaker" "$target_volume"

                # Wait for transition to complete
                while true; do
                    if [ ! -f "${SCRIPT_DIR}/volume_transition_${speaker}.pid" ]; then
                        break
                    fi
                    sleep 1
                done

                # Verify transition completed successfully
                if [ -f "${SCRIPT_DIR}/volume_transition_${speaker}.log" ]; then
                    local log_contents=$(cat "${SCRIPT_DIR}/volume_transition_${speaker}.log")
                    if echo "$log_contents" | grep -q "ERROR"; then
                        echo "Error: Volume transition failed"
                        cat "${SCRIPT_DIR}/volume_transition_${speaker}.log"
                        exit 1
                    fi
                fi

                # Clean up any remaining files
                rm -f "${SCRIPT_DIR}/volume_transition_${speaker}.pid"
                rm -f "${SCRIPT_DIR}/volume_transition_${speaker}.log"

                echo "Volume transition complete"
                exit 0
