# Day Objects mix analysis

`analyze_day_objects_mix.swift` accepts one PCM file or one directory of full mixes.
The default command acceptance limits are −18…−16 LUFS integrated loudness and
at most −1 dBTP true peak.

`--min-lufs`, `--max-lufs`, and `--max-dbtp` replace the corresponding command
acceptance limits. They may loosen or tighten those limits. Every other quality
issue still fails command acceptance, as do nonfinite samples. The embedded
`quality.issues` retains the analyzer's default diagnostic thresholds;
`files[].passesIntegratedLoudness`, `files[].passesTruePeak`, and the top-level
`passes` use the chosen command limits. Therefore a custom accepted report may still contain a default loudness
or peak diagnostic issue. Exit status is 0 for command acceptance, 2 for a failed
quality gate, and 64 for invalid input or an analysis error.

With `--stems-directory`, provide one full-mix file and explicitly identify the
active roles with `--active-stems rhythm,bass,harmony,happenings,lead` (or a
nonempty subset). The directory must contain all five named stems; intentionally
inactive stems are omitted from audibility and masking acceptance checks.

Run `ruby Scripts/day_objects_audio/test_analyze_day_objects_mix.rb` from the
repository to check the real command parser and report acceptance logic. These
checks compile the CLI with its entry point disabled and use in-memory report
fixtures. They never open or create audio files.
