# Mix TCP

A mix tool to apply Test Case Prioritization to tests, and run only the first N tests.


## Setup

The tool has two parts: server and Mix task. We will need to setup both.

### Server

The server communicates with the Mix task using the [Erlang Distribution protocol](https://www.erlang.org/doc/apps/erts/erl_dist_protocol.html). This means that we need to start the server with a name and a cookie. For example:

```bash
iex --sname tcp@localhost --cookie 12345 -S mix
```

This will start the server in dev mode from the project root. The server will use the `model_params.bin` from the current folder and will use the test runs folder provided in the Mix task.

### Mix Task

To use the Mix task, install it using `mix archive.install`.

Then just run providing the number of test files to execute, the server and the cookie, For example:

```
MIX_ENV=test mix tcp -n 8 -s tcp@localhost -c 12345 -f $(pwd)/test_runs > 2023_11_16_13_34
```

This command will also save the current execution in a new test run file.

## Observations

- the test run files will need to be cleaned up a bit, as the parser is minimalistic, one will need to have a file looking like this:
```plaintext
Example.TestFile1 [test/example/test_file1.exs]
  * test testcasename1 [L#5]
  * test testcasename1 (11.2ms) [L#5]

Example.TestFile2 [test/example/test_file2.exs]
  * test another_testcase1 [L#6]
  * test another_testcase1 (10.3ms) [L#6]
  * test another_testcase2 [L#14]
  * test another_testcase2 (0.1ms) [L#14]
```
- in order to avoid problems it is better to have the new test run outside the test run folder during execution, then after cleaning it can be moved to the test run folder
