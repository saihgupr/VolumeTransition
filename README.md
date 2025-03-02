<h1>VolumeTransition</h1>

<p>VolumeTransition is a bash script that provides smooth volume transitions for media players using the Home Assistant API. It includes robust error handling, PID management for concurrent transitions, logging, and special volume adjustments for Raspberry Pi speakers.</p>

<h2>Features</h2>

<ul>
    <li>Smooth volume transitions with configurable step size and interval</li>
    <li>Concurrent transition management using PID files</li>
    <li>Robust error handling for:
        <ul>
            <li>File permissions</li>
            <li>API connectivity</li>
            <li>Transition timeouts</li>
            <li>Stuck transitions</li>
        </ul>
    </li>
    <li>Special volume adjustments for Raspberry Pi speakers to handle hardware-specific volume quirks</li>
    <li>State monitoring to cancel transitions if speaker stops playing</li>
    <li>JSON-based transition tracking</li>
    <li>Detailed logging for debugging</li>
    <li>Maximum runtime limit to prevent infinite transitions</li>
</ul>

<h2>Requirements</h2>

<ul>
    <li>bash (tested on Linux/macOS)</li>
    <li>Home Assistant instance with API access</li>
    <li>Required tools:
        <ul>
            <li><code>curl</code> (for API communication)</li>
            <li><code>jq</code> (for JSON parsing)</li>
            <li><code>bc</code> (for floating-point calculations)</li>
        </ul>
    </li>
    <li>Write permissions in script directory</li>
    <li>Valid Home Assistant API token (Bearer token)</li>
</ul>


<h2>Usage</h2>

<p>Run the script with speaker name and target volume:</p>
<pre><code class="language-bash">./volume_transition.sh &lt;speaker_name&gt; &lt;target_volume&gt;</code></pre>

<p>Example:</p>
<pre><code class="language-bash">./volume_transition.sh living_room_speaker 0.5</code></pre>

<p>The script will:</p>
<ol>
    <li>Check for existing transitions and clean up if necessary</li>
    <li>Verify speaker state (must be playing)</li>
    <li>Start smooth volume transition to target volume</li>
    <li>Monitor for interruptions (state changes, timeouts, stuck transitions)</li>
    <li>Log progress to <code>volume_transition_&lt;speaker&gt;.log</code></li>
</ol>

<h2>How It Works</h2>

<ul>
    <li><strong>Transition Management</strong>:
        <ul>
            <li>Uses PID files to track running transitions</li>
            <li>Kills previous transitions before starting new ones</li>
            <li>Stores transition state in <code>transitions.json</code></li>
        </ul>
    </li>
    <li><strong>Volume Control</strong>:
        <ul>
            <li>Fetches current volume via Home Assistant API</li>
            <li>Calculates incremental changes using <code>bc</code></li>
            <li>Special handling for Raspberry Pi speakers:
                <ul>
                    <li>Jumps over problematic volume ranges (29-31%, 57-58%)</li>
                </ul>
            </li>
        </ul>
    </li>
    <li><strong>Error Handling</strong>:
        <ul>
            <li>Checks file permissions and attempts to fix them</li>
            <li>Monitors speaker state to cancel if not playing</li>
            <li>Detects stuck transitions and timeouts</li>
            <li>Provides detailed debug output</li>
        </ul>
    </li>
    <li><strong>Logging</strong>:
        <ul>
            <li>Creates per-speaker log files</li>
            <li>Includes transition details and error messages</li>
        </ul>
    </li>
</ul>

<h2>Notes</h2>

<ul>
    <li>Requires write permissions for PID, log, and JSON files in script directory</li>
    <li>May require sudo for initial file creation/permissions</li>
    <li>Raspberry Pi-specific adjustments may need tuning for different hardware</li>
    <li>Ensure Home Assistant API is accessible and token is valid</li>
    <li>Log files are created per speaker and cleaned up on completion</li>
</ul>

<h2>License</h2>

<p>MIT License - see <a href="LICENSE">LICENSE</a> file for details</p>

<h2>Issues</h2>

<p>Report bugs or feature requests in the <a href="https://github.com/yourusername/VolumeTransition/issues">Issues</a> section.</p>
