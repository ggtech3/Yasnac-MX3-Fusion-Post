/**
  Copyright (C) 2012-2016 by Autodesk, Inc.
  All rights reserved.

  YASNAC post processor configuration.

  $Revision: 40607 $
  $Date: 2016-01-15 19:23:40 +0100 (fr, 15 jan 2016) $
  
  FORKID {DD9126B2-C114-4561-A3AB-5D4ABDB03C80}
  
  ggtech-V1
  original
  ggtech-v2
  moved coolant after z moves above part
  
*/

description = "Generic YASNAC";
vendor = "Yaskawa";
vendorUrl = "http://yaskawa.com";
legal = "Copyright (C) 2012-2016 by Autodesk, Inc.";
certificationLevel = 2;
minimumRevision = 24000;

extension = "nc";
programNameIsInteger = true;
setCodePage("ascii");

tolerance = spatial(0.002, MM);

minimumChordLength = spatial(0.01, MM);
minimumCircularRadius = spatial(0.01, MM);
maximumCircularRadius = spatial(1000, MM);
minimumCircularSweep = toRad(0.01);
maximumCircularSweep = toRad(180);
allowHelicalMoves = true;
allowedCircularPlanes = undefined; // allow any circular motion



// user-defined properties
properties = {
  writeMachine: true, // write machine
  writeTools: true, // writes the tools
  preloadTool: false, // preloads next tool on tool change if any
  showSequenceNumbers: true, // show sequence numbers
  sequenceNumberStart: 10, // first sequence number
  sequenceNumberIncrement: 5, // increment for sequence numbers
  optionalStop: true, // optional stop
  PM4012D7: false, // specifies that the address is "P" instead of "J" for G54->G59
  separateWordsWithSpace: true // specifies that the words should be separated with a white space
};



var permittedCommentChars = " ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.,=_-";

var mapCoolantTable = new Table(
  [9, 8],
  {initial:COOLANT_OFF, force:true},
  "Invalid coolant mode"
);

var gFormat = createFormat({prefix:"G", width:2, zeropad:true, decimals:0});
var mFormat = createFormat({prefix:"M", width:2, zeropad:true, decimals:0});
var hFormat = createFormat({prefix:"H", width:2, zeropad:true, decimals:0});
var dFormat = createFormat({prefix:"D", width:2, zeropad:true, decimals:0});

var xyzFormat = createFormat({decimals:(unit == MM ? 3 : 4), forceDecimal:true});
var abcFormat = createFormat({decimals:3, forceDecimal:true, scale:DEG});
var feedFormat = createFormat({decimals:(unit == MM ? 0 : 1), forceDecimal:true});
var toolFormat = createFormat({width:1, zeropad:false, decimals:0}); // change to 2 for old controls
var rpmFormat = createFormat({decimals:0});
var pitchFormat = createFormat({decimals:(unit == MM ? 3 : 4)});
var secFormat = createFormat({decimals:3, forceDecimal:true}); // seconds - range 0.001-999999.999
var milliFormat = createFormat({decimals:0}); // milliseconds // range 1-9999
var taperFormat = createFormat({decimals:1, scale:DEG});

var xOutput = createVariable({prefix:"X"}, xyzFormat);
var yOutput = createVariable({prefix:"Y"}, xyzFormat);
var zOutput = createVariable({prefix:"Z"}, xyzFormat);
var aOutput = createVariable({prefix:"A"}, abcFormat);
var bOutput = createVariable({prefix:"B"}, abcFormat);
var cOutput = createVariable({prefix:"C"}, abcFormat);
var feedOutput = createVariable({prefix:"F"}, feedFormat);
var sOutput = createVariable({prefix:"S", force:true}, rpmFormat);
var dOutput = createVariable({}, dFormat);

// circular output
var iOutput = createReferenceVariable({prefix:"I"}, xyzFormat);
var jOutput = createReferenceVariable({prefix:"J"}, xyzFormat);
var kOutput = createReferenceVariable({prefix:"K"}, xyzFormat);

var gMotionModal = createModal({}, gFormat); // modal group 1 // G0-G3, ...
var gPlaneModal = createModal({onchange:function () {gMotionModal.reset();}}, gFormat); // modal group 2 // G17-19
var gAbsIncModal = createModal({}, gFormat); // modal group 3 // G90-91
var gFeedModeModal = createModal({}, gFormat); // modal group 5 // G93-94
var gUnitModal = createModal({}, gFormat); // modal group 6 // G20-21
var gCycleModal = createModal({}, gFormat); // modal group 9 // G81, ...
var gRetractModal = createModal({}, gFormat); // modal group 10 // G98-99

// fixed settings
var forceMultiAxisIndexing = false; // force multi-axis indexing for 3D programs
var preferPositiveTilt = false;

var WARNING_WORK_OFFSET = 0;

// collected state
var sequenceNumber;
var currentWorkOffset;

/**
  Writes the specified block.
*/
function writeBlock() {
  if (properties.showSequenceNumbers) {
    writeWords2("N" + sequenceNumber, arguments);
    sequenceNumber += properties.sequenceNumberIncrement;
  } else {
    writeWords(arguments);
  }
}

/**
  Output a comment.
*/
function writeComment(text) {
  writeln("(" + filterText(String(text).toUpperCase(), permittedCommentChars) + ")");
}

function onOpen() {

  if (false) { // note: setup your machine here
    var aAxis = createAxis({coordinate:0, table:false, axis:[1, 0, 0], range:[-360,360], preference:1});
    var cAxis = createAxis({coordinate:2, table:false, axis:[0, 0, 1], range:[-360,360], preference:1});
    machineConfiguration = new MachineConfiguration(aAxis, cAxis);

    setMachineConfiguration(machineConfiguration);
    optimizeMachineAngles2(0); // TCP mode
  }

  if (!machineConfiguration.isMachineCoordinate(0)) {
    aOutput.disable();
  }
  if (!machineConfiguration.isMachineCoordinate(1)) {
    bOutput.disable();
  }
  if (!machineConfiguration.isMachineCoordinate(2)) {
    cOutput.disable();
  }
  
  if (!properties.separateWordsWithSpace) {
    setWordSeparator("");
  }

  sequenceNumber = properties.sequenceNumberStart;
  writeln("%");

  if (programName) {
    var programId;
    try {
      programId = getAsInt(programName);
    } catch(e) {
      error(localize("Program name must be a number."));
      return;
    }
    if (!((programId >= 1) && (programId <= 99999))) {
      error(localize("Program number is out of range."));
    }
    var oFormat = createFormat({width:4, zeropad:true, decimals:0});
    if (programComment) {
      writeln("O" + oFormat.format(programId) + " (" + programComment + ")");
    } else {
      writeln("O" + oFormat.format(programId));
    }
  } else {
    error(localize("Program name has not been specified."));
    return;
  }

  // dump machine configuration
  var vendor = machineConfiguration.getVendor();
  var model = machineConfiguration.getModel();
  var description = machineConfiguration.getDescription();

  if (properties.writeMachine && (vendor || model || description)) {
    writeComment(localize("Machine"));
    if (vendor) {
      writeComment("  " + localize("vendor") + ": " + vendor);
    }
    if (model) {
      writeComment("  " + localize("model") + ": " + model);
    }
    if (description) {
      writeComment("  " + localize("description") + ": "  + description);
    }
  }

  // dump tool information
  if (properties.writeTools) {
    var zRanges = {};
    if (is3D()) {
      var numberOfSections = getNumberOfSections();
      for (var i = 0; i < numberOfSections; ++i) {
        var section = getSection(i);
        var zRange = section.getGlobalZRange();
        var tool = section.getTool();
        if (zRanges[tool.number]) {
          zRanges[tool.number].expandToRange(zRange);
        } else {
          zRanges[tool.number] = zRange;
        }
      }
    }

    var tools = getToolTable();
    if (tools.getNumberOfTools() > 0) {
      for (var i = 0; i < tools.getNumberOfTools(); ++i) {
        var tool = tools.getTool(i);
        var comment = "T" + toolFormat.format(tool.number) + " " +
          "D=" + xyzFormat.format(tool.diameter) + " " +
          localize("CR") + "=" + xyzFormat.format(tool.cornerRadius);
        if ((tool.taperAngle > 0) && (tool.taperAngle < Math.PI)) {
          comment += " " + localize("TAPER") + "=" + taperFormat.format(tool.taperAngle) + localize("deg");
        }
        if (zRanges[tool.number]) {
          comment += " - " + localize("ZMIN") + "=" + xyzFormat.format(zRanges[tool.number].getMinimum());
        }
        comment += " - " + getToolTypeName(tool.type);
        writeComment(comment);
      }
    }
  }
  
  if (false) {
    // check for duplicate tool number
    for (var i = 0; i < getNumberOfSections(); ++i) {
      var sectioni = getSection(i);
      var tooli = sectioni.getTool();
      for (var j = i + 1; j < getNumberOfSections(); ++j) {
        var sectionj = getSection(j);
        var toolj = sectionj.getTool();
        if (tooli.number == toolj.number) {
          if (xyzFormat.areDifferent(tooli.diameter, toolj.diameter) ||
              xyzFormat.areDifferent(tooli.cornerRadius, toolj.cornerRadius) ||
              abcFormat.areDifferent(tooli.taperAngle, toolj.taperAngle) ||
              (tooli.numberOfFlutes != toolj.numberOfFlutes)) {
            error(
              subst(
                localize("Using the same tool number for different cutter geometry for operation '%1' and '%2'."),
                sectioni.hasParameter("operation-comment") ? sectioni.getParameter("operation-comment") : ("#" + (i + 1)),
                sectionj.hasParameter("operation-comment") ? sectionj.getParameter("operation-comment") : ("#" + (j + 1))
              )
            );
            return;
          }
        }
      }
    }
  }

  // absolute coordinates and feed per min
  writeBlock(gAbsIncModal.format(90));

  }

function onComment(message) {
  writeComment(message);
}

/** Force output of X, Y, and Z. */
function forceXYZ() {
  xOutput.reset();
  yOutput.reset();
  zOutput.reset();
}

/** Force output of A, B, and C. */
function forceABC() {
  aOutput.reset();
  bOutput.reset();
  cOutput.reset();
}

/** Force output of X, Y, Z, A, B, C, and F on next output. */
function forceAny() {
  forceXYZ();
  forceABC();
  feedOutput.reset();
}

function onParameter(name, value) {
}

var currentWorkPlaneABC = undefined;

function forceWorkPlane() {
  currentWorkPlaneABC = undefined;
}

function setWorkPlane(abc) {
  if (!forceMultiAxisIndexing && is3D() && !machineConfiguration.isMultiAxisConfiguration()) {
    return; // ignore
  }

  if (!((currentWorkPlaneABC == undefined) ||
        abcFormat.areDifferent(abc.x, currentWorkPlaneABC.x) ||
        abcFormat.areDifferent(abc.y, currentWorkPlaneABC.y) ||
        abcFormat.areDifferent(abc.z, currentWorkPlaneABC.z))) {
    return; // no change
  }

  onCommand(COMMAND_UNLOCK_MULTI_AXIS);

  // NOTE: add retract here

  writeBlock(
    gMotionModal.format(0),
    conditional(machineConfiguration.isMachineCoordinate(0), "A" + abcFormat.format(abc.x)),
    conditional(machineConfiguration.isMachineCoordinate(1), "B" + abcFormat.format(abc.y)),
    conditional(machineConfiguration.isMachineCoordinate(2), "C" + abcFormat.format(abc.z))
  );
  
  onCommand(COMMAND_LOCK_MULTI_AXIS);

  currentWorkPlaneABC = abc;
}

var closestABC = false; // choose closest machine angles
var currentMachineABC;

function getWorkPlaneMachineABC(workPlane) {
  var W = workPlane; // map to global frame

  var abc = machineConfiguration.getABC(W);
  if (closestABC) {
    if (currentMachineABC) {
      abc = machineConfiguration.remapToABC(abc, currentMachineABC);
    } else {
      abc = machineConfiguration.getPreferredABC(abc);
    }
  } else {
    abc = machineConfiguration.getPreferredABC(abc);
  }
  
  try {
    abc = machineConfiguration.remapABC(abc);
    currentMachineABC = abc;
  } catch (e) {
    error(
      localize("Machine angles not supported") + ":"
      + conditional(machineConfiguration.isMachineCoordinate(0), " A" + abcFormat.format(abc.x))
      + conditional(machineConfiguration.isMachineCoordinate(1), " B" + abcFormat.format(abc.y))
      + conditional(machineConfiguration.isMachineCoordinate(2), " C" + abcFormat.format(abc.z))
    );
  }
  
  var direction = machineConfiguration.getDirection(abc);
  if (!isSameDirection(direction, W.forward)) {
    error(localize("Orientation not supported."));
  }
  
  if (!machineConfiguration.isABCSupported(abc)) {
    error(
      localize("Work plane is not supported") + ":"
      + conditional(machineConfiguration.isMachineCoordinate(0), " A" + abcFormat.format(abc.x))
      + conditional(machineConfiguration.isMachineCoordinate(1), " B" + abcFormat.format(abc.y))
      + conditional(machineConfiguration.isMachineCoordinate(2), " C" + abcFormat.format(abc.z))
    );
  }

  var tcp = false;
  if (tcp) {
    setRotation(W); // TCP mode
  } else {
    var O = machineConfiguration.getOrientation(abc);
    var R = machineConfiguration.getRemainingOrientation(abc, W);
    setRotation(R);
  }
  
  return abc;
}

function onSection() {
  var insertToolCall = isFirstSection() ||
    currentSection.getForceToolChange && currentSection.getForceToolChange() ||
    (tool.number != getPreviousSection().getTool().number);
  
  var retracted = false; // specifies that the tool has been retracted to the safe plane
  var newWorkOffset = isFirstSection() ||
    (getPreviousSection().workOffset != currentSection.workOffset); // work offset changes
  var newWorkPlane = isFirstSection() ||
    !isSameDirection(getPreviousSection().getGlobalFinalToolAxis(), currentSection.getGlobalInitialToolAxis());
  if (insertToolCall || newWorkOffset || newWorkPlane) {
    
    // stop spindle before retract during tool change
    if (insertToolCall && !isFirstSection()) {
      onCommand(COMMAND_STOP_SPINDLE);
    }
    
    // retract to safe plane
   // retracted = true;
   // writeBlock(gFormat.format(28), gAbsIncModal.format(91), "Z" + xyzFormat.format(0)); // retract
   //writeBlock(gAbsIncModal.format(90));
   // forceXYZ();
  }

  if (hasParameter("operation-comment")) {
    var comment = getParameter("operation-comment");
    if (comment) {
      writeComment(comment);
    }
  }
  
  if (properties.showNotes && hasParameter("notes")) {
    var notes = getParameter("notes");
    if (notes) {
      var lines = String(notes).split("\n");
      var r1 = new RegExp("^[\\s]+", "g");
      var r2 = new RegExp("[\\s]+$", "g");
      for (line in lines) {
        var comment = lines[line].replace(r1, "").replace(r2, "");
        if (comment) {
          writeComment(comment);
        }
      }
    }
  }
  
  if (insertToolCall) {
    forceWorkPlane();
    
    retracted = true;
    onCommand(COMMAND_COOLANT_OFF);
  
    if (!isFirstSection() && properties.optionalStop) {
      onCommand(COMMAND_OPTIONAL_STOP);
    }

    if (tool.number > 99) {
      warning(localize("Tool number exceeds maximum value."));
    }

    writeBlock("T" + toolFormat.format(tool.number), mFormat.format(6));
    if (tool.comment) {
      writeComment(tool.comment);
    }
    var showToolZMin = false;
    if (showToolZMin) {
      if (is3D()) {
        var numberOfSections = getNumberOfSections();
        var zRange = currentSection.getGlobalZRange();
        var number = tool.number;
        for (var i = currentSection.getId() + 1; i < numberOfSections; ++i) {
          var section = getSection(i);
          if (section.getTool().number != number) {
            break;
          }
          zRange.expandToRange(section.getGlobalZRange());
        }
        writeComment(localize("ZMIN") + "=" + zRange.getMinimum());
      }
    }

    if (properties.preloadTool) {
      var nextTool = getNextTool(tool.number);
      if (nextTool) {
        writeBlock("T" + toolFormat.format(nextTool.number));
      } else {
        // preload first tool
        var section = getSection(0);
        var firstToolNumber = section.getTool().number;
        if (tool.number != firstToolNumber) {
          writeBlock("T" + toolFormat.format(firstToolNumber));
        }
      }
    }
  }
  
  if (insertToolCall ||
      isFirstSection() ||
      (rpmFormat.areDifferent(tool.spindleRPM, sOutput.getCurrent())) ||
      (tool.clockwise != getPreviousSection().getTool().clockwise)) {
    if (tool.spindleRPM < 1) {
      error(localize("Spindle speed out of range."));
      return;
    }
    if (tool.spindleRPM > 99999) {
      warning(localize("Spindle speed exceeds maximum value."));
    }
    writeBlock(
      sOutput.format(tool.spindleRPM), mFormat.format(tool.clockwise ? 3 : 4)
    );

    onCommand(COMMAND_START_CHIP_TRANSPORT);
    if (forceMultiAxisIndexing || !is3D() || machineConfiguration.isMultiAxisConfiguration()) {
      // writeBlock(mFormat.format(xxx)); // shortest path traverse
    }
  }

  // wcs
  if (insertToolCall) { // force work offset when changing tool
    currentWorkOffset = undefined;
  }
  var workOffset = currentSection.workOffset;
  if (workOffset == 0) {
    warningOnce(localize("Work offset has not been specified. Using G54 as WCS."), WARNING_WORK_OFFSET);
    workOffset = 1;
  }
  if (workOffset > 0) {
    var address = properties.PM4012D7 ? "P" : "J";
    var code = (workOffset - 1) % 6;
    var j = (((workOffset - 1)/6) | 0) + 1;
    if (j > 27) {
      error(localize("Work offset out of range."));
    }
    if (workOffset != currentWorkOffset) {
      currentWorkOffset = workOffset;
      if (j > 1) {
        writeBlock(gFormat.format(54 + code), address + j);
      } else {
        if ((54 + code) != currentWorkOffset) {
          writeBlock(gFormat.format(54 + code)); // G54->G59 (J0 or J1)
          currentWorkOffset = (54 + code);
        }
      }
    }
  }

  forceXYZ();

  if (forceMultiAxisIndexing || !is3D() || machineConfiguration.isMultiAxisConfiguration()) { // use 5-axis indexing for multi-axis mode
    // set working plane after datum shift

    var abc = new Vector(0, 0, 0);
    if (currentSection.isMultiAxis()) {
      forceWorkPlane();
      cancelTransformation();
    } else {
      abc = getWorkPlaneMachineABC(currentSection.workPlane);
    }
    setWorkPlane(abc);
  } else { // pure 3D
    var remaining = currentSection.workPlane;
    if (!isSameDirection(remaining.forward, new Vector(0, 0, 1))) {
      error(localize("Tool orientation is not supported."));
      return;
    }
    setRotation(remaining);
  }

  // set coolant after we have positioned at Z
//  {
//    var c = mapCoolantTable.lookup(tool.coolant);
//    if (c) {
//      writeBlock(mFormat.format(c));
//    } else {
//      warning(localize("Coolant not supported."));
//    }
//  }

  forceAny();
  gMotionModal.reset();

  var initialPosition = getFramePosition(currentSection.getInitialPosition());
  if (!retracted) {
    if (getCurrentPosition().z < initialPosition.z) {
      writeBlock(gMotionModal.format(0), zOutput.format(initialPosition.z));
    }
  }

  if (insertToolCall || retracted) {
    var lengthOffset = tool.lengthOffset;
    if (lengthOffset > 1199) {
      error(localize("Length offset out of range."));
      return;
    }

    gMotionModal.reset();
    writeBlock(gPlaneModal.format(17));
    
    if (!machineConfiguration.isHeadConfiguration()) {
      writeBlock(
        gAbsIncModal.format(90),
        gMotionModal.format(0), xOutput.format(initialPosition.x), yOutput.format(initialPosition.y)
      );
      writeBlock(gMotionModal.format(0), gFormat.format(43), zOutput.format(initialPosition.z), hFormat.format(lengthOffset));
    } else {
      writeBlock(
        gAbsIncModal.format(90),
        gMotionModal.format(0),
        gFormat.format(43), xOutput.format(initialPosition.x),
        yOutput.format(initialPosition.y),
        zOutput.format(initialPosition.z), hFormat.format(lengthOffset)
      );
    }

  // set coolant after we have positioned at Z - ggtech moved here
  {
    var c = mapCoolantTable.lookup(tool.coolant);
    if (c) {
      writeBlock(mFormat.format(c));
    } else {
      warning(localize("Coolant not supported."));
    }
  }
  
    gMotionModal.reset();
  } else {
    writeBlock(
      gAbsIncModal.format(90),
      gMotionModal.format(0),
      xOutput.format(initialPosition.x),
      yOutput.format(initialPosition.y)
    );
  }
}

function onDwell(seconds) {
  if (seconds > 999999.999) {
    warning(localize("Dwelling time is out of range."));
  }
  seconds = clamp(0.001, seconds, 999999.999);
  if (seconds >= 1) {
    writeBlock(gFeedModeModal.format(94), gFormat.format(4), "P" + secFormat.format(seconds));
  } else {
    writeBlock(gFeedModeModal.format(94), gFormat.format(4), "P" + milliFormat.format(seconds * 1000));
  }
}

function onSpindleSpeed(spindleSpeed) {
  writeBlock(sOutput.format(spindleSpeed));
}

function onCycle() {
  writeBlock(gPlaneModal.format(17));
}

function getCommonCycle(x, y, z, r) {
  forceXYZ();
  return [xOutput.format(x), yOutput.format(y),
    zOutput.format(z),
    "R" + xyzFormat.format(r)];
}

function onCyclePoint(x, y, z) {
  if (isFirstCyclePoint()) {
    repositionToCycleClearance(cycle, x, y, z);
    
    // return to initial Z which is clearance plane and set absolute mode

    var F = cycle.feedrate;
    var P = (cycle.dwell == 0) ? 0 : clamp(1, cycle.dwell * 1000, 99999999); // in milliseconds

    switch (cycleType) {
    case "drilling":
      writeBlock(
        gPlaneModal.format(17), gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(81),
        getCommonCycle(x, y, z, cycle.retract),
        feedOutput.format(F)
      );
      break;
    case "counter-boring":
      if (P > 0) {
        writeBlock(
          gPlaneModal.format(17), gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(82),
          getCommonCycle(x, y, z, cycle.retract),
          "P" + milliFormat.format(P),
          feedOutput.format(F)
        );
      } else {
        writeBlock(
          gPlaneModal.format(17), gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(81),
          getCommonCycle(x, y, z, cycle.retract),
          feedOutput.format(F)
        );
      }
      break;
    case "chip-breaking":
      // cycle.accumulatedDepth is ignored
      writeBlock(
        gPlaneModal.format(17), gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(73),
        getCommonCycle(x, y, z, cycle.retract),
        "Q" + xyzFormat.format(cycle.incrementalDepth),
        conditional(P > 0, "P" + milliFormat.format(P)), // optional
        feedOutput.format(F)
      );
      break;
    case "deep-drilling":
      writeBlock(
        gPlaneModal.format(17), gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(83),
        getCommonCycle(x, y, z, cycle.retract),
        "Q" + xyzFormat.format(cycle.incrementalDepth),
        "P" + milliFormat.format(P),
        feedOutput.format(F)
      );
      break;
    case "tapping":
      writeBlock(mFormat.format((tool.type == TOOL_TAP_LEFT_HAND) ? 4 : 3));
      writeBlock(gFeedModeModal.format(93));
      writeBlock(
        gPlaneModal.format(17), gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format((tool.type == TOOL_TAP_LEFT_HAND) ? 74 : 84),
        getCommonCycle(x, y, z, cycle.retract),
        "F" + pitchFormat.format(tool.threadPitch),
        sOutput.format(tool.spindleRPM)
      );
      break;
    case "left-tapping":
      writeBlock(mFormat.format(4)); // TAG: make sure M04 is active
      writeBlock(gFeedModeModal.format(93));
      writeBlock(
        gPlaneModal.format(17), gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(74),
        getCommonCycle(x, y, z, cycle.retract),
        "F" + pitchFormat.format(tool.threadPitch),
        sOutput.format(tool.spindleRPM)
      );
      break;
    case "right-tapping":
      writeBlock(mFormat.format(3)); // TAG: make sure M03 is active
      writeBlock(gFeedModeModal.format(93));
      writeBlock(
        gPlaneModal.format(17), gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(84),
        getCommonCycle(x, y, z, cycle.retract),
        "F" + pitchFormat.format(tool.threadPitch),
        sOutput.format(tool.spindleRPM)
      );
      break;
    case "fine-boring":
      // I/J are supported by G76
      writeBlock(
        gPlaneModal.format(17), gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(76),
        getCommonCycle(x, y, z, cycle.retract),
        "P" + milliFormat.format(P), // not optional
        "Q" + xyzFormat.format(cycle.shift),
        feedOutput.format(F)
      );
      break;
    case "back-boring":
      // I/J are supported by G77
      if (P > 0) {
        expandCyclePoint(x, y, z);
      } else {
        var dx = (gPlaneModal.getCurrent() == 19) ? cycle.backBoreDistance : 0;
        var dy = (gPlaneModal.getCurrent() == 18) ? cycle.backBoreDistance : 0;
        var dz = (gPlaneModal.getCurrent() == 17) ? cycle.backBoreDistance : 0;
        writeBlock(
          gPlaneModal.format(17), gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(77),
          getCommonCycle(x - dx, y - dy, z - dz, cycle.bottom),
          "Q" + xyzFormat.format(cycle.shift),
          feedOutput.format(F)
        );
      }
      break;
    case "reaming":
      if (P > 0) {
        writeBlock(
          gPlaneModal.format(17), gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(89),
          getCommonCycle(x, y, z, cycle.retract),
          "P" + milliFormat.format(P), // not optional
          feedOutput.format(F),
          "E" + feedFormat.format(cycle.retractFeedrate)
        );
      } else {
        writeBlock(
          gPlaneModal.format(17), gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(85),
          getCommonCycle(x, y, z, cycle.retract),
          feedOutput.format(F),
          "E" + feedFormat.format(cycle.retractFeedrate)
        );
      }
      break;
    case "stop-boring":
      if (P > 0) {
        expandCyclePoint(x, y, z);
      } else {
        writeBlock(
          gPlaneModal.format(17), gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(86),
          getCommonCycle(x, y, z, cycle.retract),
          feedOutput.format(F)
        );
      }
      break;
    case "manual-boring":
      if (P > 0) {
        writeBlock(
          gPlaneModal.format(17), gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(88),
          getCommonCycle(x, y, z, cycle.retract),
          "P" + milliFormat.format(P), // not optional
          feedOutput.format(F)
        );
      } else {
        writeBlock(
          gPlaneModal.format(17), gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(87),
          getCommonCycle(x, y, z, cycle.retract),
          feedOutput.format(F)
        );
      }
      break;
    case "boring":
      if (P > 0) {
        writeBlock(
          gPlaneModal.format(17), gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(89),
          getCommonCycle(x, y, z, cycle.retract),
          "P" + milliFormat.format(P), // not optional
          feedOutput.format(F) /*,
          "E" + feedFormat.format(cycle.retractFeedrate)*/
        );
      } else {
        writeBlock(
          gPlaneModal.format(17), gRetractModal.format(98), gAbsIncModal.format(90), gCycleModal.format(86),
          getCommonCycle(x, y, z, cycle.retract),
          feedOutput.format(F) /*,
          "E" + feedFormat.format(cycle.retractFeedrate)*/
        );
      }
      break;
    default:
      expandCyclePoint(x, y, z);
    }
  } else {
    if (cycleExpanded) {
      expandCyclePoint(x, y, z);
    } else {
      writeBlock(xOutput.format(x), yOutput.format(y));
    }
  }
}

function onCycleEnd() {
  if (!cycleExpanded) {
    writeBlock(gCycleModal.format(80));
    if (gFeedModeModal.getCurrent() != 94) { // this is only here in case gFeedModeModal is set to non-modal
      writeBlock(gFeedModeModal.format(94));
    }
    zOutput.reset();
  }
}

var pendingRadiusCompensation = -1;

function onRadiusCompensation() {
  pendingRadiusCompensation = radiusCompensation;
}

function onRapid(_x, _y, _z) {
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  if (x || y || z) {
    if (pendingRadiusCompensation >= 0) {
      error(localize("Radius compensation mode cannot be changed at rapid traversal."));
      return;
    }
    writeBlock(gMotionModal.format(0), x, y, z);
    feedOutput.reset();
  }
}

function onLinear(_x, _y, _z, feed) {
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  var f = feedOutput.format(feed);
  if (x || y || z) {
    if (pendingRadiusCompensation >= 0) {
      pendingRadiusCompensation = -1;
      var d = tool.diameterOffset;
      if (d > 1199) {
        warning(localize("The diameter offset exceeds the maximum value."));
      }
      writeBlock(gPlaneModal.format(17));
      switch (radiusCompensation) {
      case RADIUS_COMPENSATION_LEFT:
        dOutput.reset();
        writeBlock(gMotionModal.format(1), gFormat.format(41), x, y, z, dOutput.format(d), f);
        break;
      case RADIUS_COMPENSATION_RIGHT:
        dOutput.reset();
        writeBlock(gMotionModal.format(1), gFormat.format(42), x, y, z, dOutput.format(d), f);
        break;
      default:
        writeBlock(gMotionModal.format(1), gFormat.format(40), x, y, z, f);
      }
    } else {
      writeBlock(gMotionModal.format(1), x, y, z, f);
    }
  } else if (f) {
    if (getNextRecord().isMotion()) { // try not to output feed without motion
      feedOutput.reset(); // force feed on next line
    } else {
      writeBlock(gMotionModal.format(1), f);
    }
  }
}

function onRapid5D(_x, _y, _z, _a, _b, _c) {
  if (pendingRadiusCompensation >= 0) {
    error(localize("Radius compensation mode cannot be changed at rapid traversal."));
    return;
  }
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  var a = aOutput.format(_a);
  var b = bOutput.format(_b);
  var c = cOutput.format(_c);
  writeBlock(gMotionModal.format(0), x, y, z, a, b, c);
  feedOutput.reset();
}

function onLinear5D(_x, _y, _z, _a, _b, _c, feed) {
  if (pendingRadiusCompensation >= 0) {
    error(localize("Radius compensation cannot be activated/deactivated for 5-axis move."));
    return;
  }
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  var a = aOutput.format(_a);
  var b = bOutput.format(_b);
  var c = cOutput.format(_c);
  var f = feedOutput.format(feed);
  if (x || y || z || a || b || c) {
    writeBlock(gMotionModal.format(1), x, y, z, a, b, c, f);
  } else if (f) {
    if (getNextRecord().isMotion()) { // try not to output feed without motion
      feedOutput.reset(); // force feed on next line
    } else {
      writeBlock(gMotionModal.format(1), f);
    }
  }
}

function onCircular(clockwise, cx, cy, cz, x, y, z, feed) {
  if (pendingRadiusCompensation >= 0) {
    error(localize("Radius compensation cannot be activated/deactivated for a circular move."));
    return;
  }

  var start = getCurrentPosition();

  if (isFullCircle()) {
    if (isHelical()) {
      linearize(tolerance);
      return;
    }
    switch (getCircularPlane()) {
    case PLANE_XY:
      writeBlock(gAbsIncModal.format(90), gPlaneModal.format(17), gMotionModal.format(clockwise ? 2 : 3), iOutput.format(cx - start.x, 0), jOutput.format(cy - start.y, 0), feedOutput.format(feed));
      break;
    case PLANE_ZX:
      writeBlock(gAbsIncModal.format(90), gPlaneModal.format(18), gMotionModal.format(clockwise ? 2 : 3), iOutput.format(cx - start.x, 0), kOutput.format(cz - start.z, 0), feedOutput.format(feed));
      break;
    case PLANE_YZ:
      writeBlock(gAbsIncModal.format(90), gPlaneModal.format(19), gMotionModal.format(clockwise ? 2 : 3), jOutput.format(cy - start.y, 0), kOutput.format(cz - start.z, 0), feedOutput.format(feed));
      break;
    default:
      linearize(tolerance);
    }
  } else {
    switch (getCircularPlane()) {
    case PLANE_XY:
      writeBlock(gAbsIncModal.format(90), gPlaneModal.format(17), gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y), zOutput.format(z), iOutput.format(cx - start.x, 0), jOutput.format(cy - start.y, 0), feedOutput.format(feed));
      break;
    case PLANE_ZX:
      writeBlock(gAbsIncModal.format(90), gPlaneModal.format(18), gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y), zOutput.format(z), iOutput.format(cx - start.x, 0), kOutput.format(cz - start.z, 0), feedOutput.format(feed));
      break;
    case PLANE_YZ:
      writeBlock(gAbsIncModal.format(90), gPlaneModal.format(19), gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y), zOutput.format(z), jOutput.format(cy - start.y, 0), kOutput.format(cz - start.z, 0), feedOutput.format(feed));
      break;
    default:
      linearize(tolerance);
    }
  }
}

var mapCommand = {
  COMMAND_STOP:0,
  COMMAND_OPTIONAL_STOP:1,
  COMMAND_END:2,
  COMMAND_SPINDLE_CLOCKWISE:3,
  COMMAND_SPINDLE_COUNTERCLOCKWISE:4,
  COMMAND_STOP_SPINDLE:5,
  COMMAND_ORIENTATE_SPINDLE:19,
  COMMAND_LOAD_TOOL:6,
  COMMAND_COOLANT_ON:8,
  COMMAND_COOLANT_OFF:9
};

function onCommand(command) {
  switch (command) {
  case COMMAND_START_SPINDLE:
    onCommand(tool.clockwise ? COMMAND_SPINDLE_CLOCKWISE : COMMAND_SPINDLE_COUNTERCLOCKWISE);
    return;
  case COMMAND_LOCK_MULTI_AXIS:
    return;
  case COMMAND_UNLOCK_MULTI_AXIS:
    return;
  case COMMAND_START_CHIP_TRANSPORT:
    return;
  case COMMAND_STOP_CHIP_TRANSPORT:
    return;
  case COMMAND_BREAK_CONTROL:
    return;
  case COMMAND_TOOL_MEASURE:
    return;
  }
  
  var stringId = getCommandStringId(command);
  var mcode = mapCommand[stringId];
  if (mcode != undefined) {
    writeBlock(mFormat.format(mcode));
  } else {
    onUnsupportedCommand(command);
  }
}

function onSectionEnd() {
  writeBlock(gPlaneModal.format(17));
  forceAny();
}

function onClose() {
 onCommand(COMMAND_STOP_SPINDLE);
  onCommand(COMMAND_COOLANT_OFF);

writeBlock(gFormat.format(0),gFormat.format(49),gFormat.format(52), "X-10.", "Y0",  "Z0");
forceXYZ();

  setWorkPlane(new Vector(0, 0, 0)); // reset working plane

  onImpliedCommand(COMMAND_END);
  onImpliedCommand(COMMAND_STOP_SPINDLE);
  writeBlock(mFormat.format(30)); // stop program, spindle stop, coolant off
  writeln("%");
}
