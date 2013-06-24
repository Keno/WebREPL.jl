# input messages (to julia)
const MSG_INPUT_NULL              = 0
const MSG_INPUT_EVAL              = 1
const MSG_INPUT_REPLAY_HISTORY    = 2
const MSG_INPUT_GET_USER          = 3
const MSG_INPUT_AUTHENTICATE      = 4

# output messages (to the browser)
const MSG_OUTPUT_WELCOME          = 1
const MSG_OUTPUT_READY            = 2
const MSG_OUTPUT_MESSAGE          = 3
const MSG_OUTPUT_OTHER            = 4
const MSG_OUTPUT_EVAL_INPUT       = 5
const MSG_OUTPUT_FATAL_ERROR      = 6
const MSG_OUTPUT_EVAL_INCOMPLETE  = 7
const MSG_OUTPUT_EVAL_RESULT      = 8
const MSG_OUTPUT_EVAL_ERROR       = 9
const MSG_OUTPUT_PLOT             = 10
const MSG_OUTPUT_GET_USER         = 11
const MSG_OUTPUT_HTML             = 12
