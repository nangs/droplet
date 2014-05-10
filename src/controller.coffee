# Copyright (c) 2014 Anthony Bau
#
# MIT License.

define ['ice-coffee', 'ice-draw', 'ice-model'], (coffee, draw, model) ->
  # ## Magic constants
  PALETTE_TOP_MARGIN = 5
  PALETTE_MARGIN = 5
  MIN_DRAG_DISTANCE = 5
  PALETTE_LEFT_MARGIN = 5
  PALETTE_WIDTH = 300
  DEFAULT_INDENT_DEPTH = 2
  ANIMATION_FRAME_RATE = 60

  exports = {}

  # FOUNDATION
  # ================================

  # ## Editor event bindings
  #
  # These are different events associated with the Editor
  # that features will want to bind to.
  unsortedEditorBindings = {
    'populate': []

    'resize': []
    'redraw_main': []
    'redraw_palette': []

    'mousedown': []
    'mousemove': []
    'mouseup': []

    'mutation': []
  }

  unsortedEditorKeyBindings = {}

  editorBindings = {}
  
  # This hook function is for convenience,
  # for features to add events that will occur at
  # various times in the editor lifecycle.
  hook = (event, priority, fn) ->
    if event[..3] is 'key.'
      unsortedEditorKeyBindings[event[4..]] ?= []
      unsortedEditorKeyBindings[event[4..]].push {
        priority: priority
        fn: fn
      }
    else
      unsortedEditorBindings[event].push {
        priority: priority
        fn: fn
      }
  
  # ## The Editor Class
  exports.Editor = class Editor
    constructor: (@wrapperElement, @paletteGroups) ->
      # ## DOM Population
      # This stage of ICE Editor construction populates the given wrapper
      # element with all the necessary ICE editor components.
      
      # ### Wrapper
      # Create the div that will contain all the ICE Editor graphics

      @iceElement = document.createElement 'div'
      @iceElement.className = 'ice-wrapper-div'

      # We give our element a tabIndex so that it can be focused and capture keypresses.
      @iceElement.tabIndex = 0

      # Append that div.
      @wrapperElement.appendChild @iceElement

      # ### Tracker
      # Create the div that will track all the ICE editor mouse movement

      @tracker = document.createElement 'div'
      @tracker.className = 'ice-track-area'
      
      # Append that div.
      @iceElement.appendChild @tracker
      
      # ### Canvases
      # Create the palette and main canvases

      # Main canvas first
      @mainCanvas = document.createElement 'canvas'
      @mainCanvas.className = 'ice-main-canvas'

      @mainCtx = @mainCanvas.getContext '2d'
      
      @iceElement.appendChild @mainCanvas
      
      # Then palette canvas
      @paletteCanvas = document.createElement 'canvas'
      @paletteCanvas.className = 'ice-palette-canvas'

      @paletteCtx = @paletteCanvas.getContext '2d'

      @iceElement.appendChild @paletteCanvas
      
      # Call all the feature bindings that are supposed
      # to happen now.
      for binding in editorBindings.populate
        binding.call this
      
      # ## Resize
      # This stage of ICE editor construction, which is repeated
      # whenever the editor is resized, should adjust the sizes
      # of all the ICE editor componenents to fit the wrapper.
      window.addEventListener 'resize', =>
        @resize()
        @redrawMain(); @redrawPalette()

      @resize()

      # ## Tracker Events
      # We allow binding to the tracker element.
      for eventName in ['mousedown', 'mouseup', 'mousemove'] then do (eventName) =>
        @tracker.addEventListener eventName, (event) =>
          trackPoint = @getPointRelativeToTracker event
          
          # We keep a state object so that handlers
          # can know about each other.
          state = {}
          
          # Call all the handlers.
          for handler in editorBindings[eventName]
            handler.call this, trackPoint, event, state

      # We also allow binding to keypresses in the element.
      # We will use dmauro's Keypress library for keyboard-shortcut
      # input.
      @keyListener = new window.keypress.Listener @iceElement

      boundListeners = []
      
      # For each combo to which binding(s) are attached,
      # listen for that combo and execute each binding
      # attached to it.
      #
      # We will preventDefault (!executeDefault) if anyone
      # wants to preventDefault.
      for combo, fns of editorBindings.key then do (fns) =>
        @keyListener.simple_combo combo, =>
          state = {}
          
          executeDefault = true

          for fn in fns
            result = fn.call(this, state) ? true
            executeDefault and= result

          return executeDefault
      
      # ## Document initialization
      # We start of with an empty document
      @tree = new model.Segment()

      # Now that we've populated everything, immediately redraw.
      @redrawMain(); @redrawPalette()
    
    # ## Foundational Resize
    # At the editor core, we will need to resize
    # all of the natively-added canvases, as well
    # as the wrapper element, whenever a resize
    # occurs.
    resize: ->
      @iceElement.style.height = "#{@wrapperElement.offsetHeight}px"
      @iceElement.style.width ="#{ @wrapperElement.offsetWidth}px"

      @mainCanvas.height = @iceElement.offsetHeight
      @mainCanvas.width = @iceElement.offsetWidth

      @mainCanvas.style.height = "#{@mainCanvas.height}px"
      @mainCanvas.style.width = "#{@mainCanvas.width}px"
      
      @paletteCanvas.style.top = "#{@paletteHeaderHeight}px"
      @paletteCanvas.height = @iceElement.offsetHeight - @paletteHeaderHeight
      @paletteCanvas.width = PALETTE_WIDTH

      @paletteCanvas.style.height = "#{@paletteCanvas.height}px"
      @paletteCanvas.style.width = "#{@paletteCanvas.width}px"

      for binding in editorBindings.resize
        binding.call this
    
  # RENDERING CAPABILITIES
  # ================================
  
  # ## Redraw
  # There are two different redraw events, redraw_main and redraw_palette,
  # for redrawing the main canvas and palette canvas, respectively.
  # 
  # Redrawing simply involves issuing a call to the View.
    
  Editor::clearMain = ->
    @mainCtx.clearRect @scrollOffsets.main.x, @scrollOffsets.main.y, @mainCanvas.width, @mainCanvas.height

  Editor::redrawMain = ->
    unless @currentlyAnimating
      # Set our draw tool's font size
      # to the font size we want
      draw._setGlobalFontSize @fontSize

      # Supply our main canvas for measuring
      draw._setCTX @mainCtx
      
      # Clear the main canvas
      @clearMain()

      # Draw the new tree on the main context
      @tree.view.compute(); @tree.view.draw @mainCtx

      for binding in editorBindings.redraw_main
        binding.call this
    
  Editor::clearPalette = ->
      @paletteCtx.clearRect @scrollOffsets.palette.x, @scrollOffsets.palette.y, @paletteCanvas.width, @paletteCanvas.height

  Editor::redrawPalette = ->
      @clearPalette()

      # Supply our palette canvas for text measuring
      draw._setCTX @paletteCtx

      draw._setGlobalFontSize @fontSize
      
      # We will construct a vertical layout
      # with padding for the palette blocks.
      # To do this, we will need to keep track
      # of the last bottom edge of a palette block.
      lastBottomEdge = PALETTE_TOP_MARGIN

      for paletteBlock in @currentPaletteBlocks
        # Layout this block
        paletteBlock.view.compute()
        paletteBlock.view.translate new draw.Point PALETTE_LEFT_MARGIN, lastBottomEdge

        # Render the block
        paletteBlock.view.draw @paletteCtx
        
        # Update lastBottomEdge
        lastBottomEdge = paletteBlock.view.getBounds().bottom() + PALETTE_MARGIN

      for binding in editorBindings.redraw_palette
        binding.call this

  # MOUSE INTERACTION WRAPPERS
  # ================================

  # These are some common operations we need to do with
  # the mouse that will be convenient later.

  # ### getPointRelativeToTracker
  # Given a mousedown/touchstart event,
  # get its coordinates relative to the tracker element.

  Editor::getPointRelativeToTracker = (event) ->
    # There are two cases we have to deal
    # with here for browser compatability.

    # The first is Chrome and Safari.
    if event.offsetX?
      # We want this point relative to the tracker element.
      point = new draw.Point event.offsetX, event.offsetY
    
    # The second is Firefox.
    else
      point = new draw.Point event.layerX, event.layerY
    
    # Now, we want to get this point relative to the tracker element,
    # so we need to bubble up its parents until we reach it.
    target = event.target

    until target is @tracker
      point.x += target.offsetLeft - target.scrollLeft
      point.y += target.offsetTop - target.scrollTop

      target = target.offsetParent

    # Now we're done.
    return point
    
  # ### Conversion functions
  # Convert a point relative to the tracker into
  # a point relative to one of the two canvases.
  Editor::trackerPointToMain = (point) ->
    new draw.Point(
      point.x - @mainCanvas.offsetLeft + @scrollOffsets.main.x
      point.y - @mainCanvas.offsetTop + @scrollOffsets.main.y
    )

  Editor::trackerPointToPalette = (point) ->
    new draw.Point(
      point.x - @paletteCanvas.offsetLeft + @scrollOffsets.palette.x,
      point.y - @paletteCanvas.offsetTop + @scrollOffsets.palette.y
    )
    
  # ### hitTest
  # Simple function for going through a linked-list block
  # and seeing what the innermost child is that we hit.
  hitTest = (point, block) ->
    head = block.start; seek = block.end
    
    until head is seek
      if head.type is 'blockStart' and head.block.view.path.contains point
        seek = head.block.end
      head = head.next
    
    # If we had a child hit, return it.
    if head isnt block.end
      return head.block
    
    # If we didn't have a child hit, it's possible
    # that _we_ are the innermost child that hit. See if that's
    # the case.
    else if block.type is 'block' and block.view.path.contains point
      return block
    
    # Nope, it's not. Answer is null.
    else return null

  # UNDO STACK SUPPORT
  # ================================

  # We must declare a few
  # fields a populate time
  hook 'populate', 0, ->
    @undoStack = []
  
  # The UndoOperation class is the base
  # class for all undo operations.
  class UndoOperation
    constructor: ->

    # Undo and redo should return
    # the desired new cursor position.
    undo: (editor) -> editor.tree.start
    redo: (editor) -> editor.tree.start
  
  # addMicroUndoOperation pushes
  # the given operation to the undo stack,
  # and might possibly do some bureaucracy in the future.
  Editor::addMicroUndoOperation = (operation) ->
    @undoStack.push operation
    
    # We allow binding to mutation;
    # all mutation must call addMicroUndoOperation.
    for binding in editorBindings.mutation
      binding.call this
    
    # If someone has bound to mutation via
    # the public API, fire it.
    @fireEvent 'change', [operation]
  
  # The undo function pops and undoes
  # operations from the undo stack until
  # we reach a capture point.
  Editor::undo = ->
    # If the undo stack is empty, give up
    if @undoStack.length is 0 then return

    # Otherwise, try to undo the operation
    operation = @undoStack.pop()
    
    # If the operation is a capture point, stop.
    #
    # NOTE: Right now capture points are signified by the
    # string 'CAPTURE_POINT'; this may need to be changed
    # in the future.
    if operation is 'CAPTURE_POINT' then return
    else
      # Otherwise, apply the undo operation and
      # recurse.
      @moveCursorTo operation.undo this
      @undo()
    
    @redrawMain()
  
  # We'll also allow users to clear
  # the undo stack.
  Editor::clearUndoStack = ->
    @undoStack.length = 0

  # Now we hook to ctrl-z to undo.
  hook 'key.meta z', 0, ->
    @undo()

  # BASIC BLOCK MOVE SUPPORT
  # ================================
  
  # Set up the undo operation for
  # block moving.
  class PickUpOperation extends UndoOperation
    constructor: (block) ->
      @block = block.clone()
      beforeToken = block.start.prev
      
      # For the "before" location, we don't actually want
      # the thing before; we want the place at which we can
      # place the block to get it back to what it used to be.
      while beforeToken?.prev? and beforeToken.type in ['newline', 'segmentStart', 'cursor']
        beforeToken = beforeToken.prev

      @before = beforeToken?.getSerializedLocation() ? null

    undo: (editor) ->
      # If the block used to be at null, we don't need to do anything.
      unless @before? then return

      # Move a clone into position.
      (clone = @block.clone()).moveTo editor.tree.getTokenAtLocation @before
      
      # Move the cursor to the end of it.
      return clone.end

    redo: (editor) ->
      # If the operation was a no-op, redo is a no-op.
      unless @before? then return

      # Find the block we want to remove
      blockStart = editor.tree.getTokenAtLocation @before
      until blockStart.type is @block.start.type then blockStart = blockStart.next
      
      # Move it to null.
      if @block.start.type is 'segment'
        blockStart.segment.moveTo null

      else
        blockStart.block.moveTo null
      
      # Move the cursor somewhere close to what we
      # just deleted.
      return editor.tree.getTokenAtLocation @before

  class DropOperation extends UndoOperation
    constructor: (block, dest) ->
      @block = block.clone()
      @dest = dest?.getSerializedLocation() ? null
      
      if dest?.type is 'socketStart'
        @displacedSocketText = dest.socket.content()?.clone() ? null
      else @displacedSocketText = null

    undo: (editor) ->
      # If the operation was a no-op, undo is a no-op.
      unless @dest? then return

      # Find the block we want to remove
      blockStart = editor.tree.getTokenAtLocation @dest
      until blockStart.type is @block.start.type then blockStart = blockStart.next
      
      # Move it to null.
      if @block.type is 'segment'
        blockStart.segment.moveTo null

      else
        blockStart.block.moveTo null
      
      # We may need to replace some of displaced
      # socket text from dropping a block
      # into a socket. If so, do so.
      if @displacedSocketText?
        editor.tree.getTokenAtLocation(@dest).insert @displacedSocketText.clone()
      
      # Move the cursor somewhere close to what we
      # just deleted.
      return editor.tree.getTokenAtLocation @dest
    
    redo: (editor) ->
      # If the operation was a no-op, redo is a no-op.
      unless @dest? then return

      # Move a clone into position.
      (clone = @block.clone()).moveTo editor.tree.getTokenAtLocation @dest
      
      # Move the cursor to the end of it.
      return clone.end
  
  # At population-time, we will
  # want to set up a few fields.
  hook 'populate', 0, ->
    @clickedPoint = null
    @clickedBlock = null

    @draggingBlock = null
    @draggingOffset = null
    
    @lastHighlight = null

    # We will also have to initialize the
    # drag canvas.
    @dragCanvas = document.createElement 'canvas'
    @dragCanvas.className = 'ice-drag-canvas'

    @dragCtx = @dragCanvas.getContext '2d'
    
    # We append it to the tracker element,
    # so that it can appear in front of the scrollers.
    @tracker.appendChild @dragCanvas
  
  # Utility function for clearing the drag canvas,
  # an operation we will be doing a lot.
  Editor::clearDrag = ->
    @dragCtx.clearRect 0, 0, @dragCanvas.width, @dragCanvas.height

  # On resize, we will want to size the drag canvas correctly.
  hook 'resize', 0, ->
    @dragCanvas.width = @iceElement.offsetWidth * 2 - PALETTE_WIDTH
    @dragCanvas.height = @iceElement.offsetHeight
  
  # On mousedown, we will want to
  # hit test blocks in the root tree to
  # see if we want to move them.
  #
  # We do not do anything until the user
  # drags their mouse five pixels
  hook 'mousedown', 3, (point, event, state) ->
    # If someone else has already taken this click, pass.
    if state.consumedHitTest then return
    
    # Hit test against the tree.
    hitTestResult = hitTest @trackerPointToMain(point), @tree
    
    # If it came back positive,
    # deal with the click.
    if hitTestResult?
      # Record the hit test result (the block we want to pick up)
      @clickedBlock = hitTestResult

      # Move the cursor somewhere nearby
      @moveCursorTo @clickedBlock.end

      # Record the point at which is was clicked (for clickedBlock->draggingBlock)
      @clickedPoint = point
    
      # Signify to any other hit testing
      # handlers that we have already consumed
      # the hit test opportunity for this event.
      state.consumedHitTest = true
  
  # If the user lifts the mouse
  # before they have dragged five pixels,
  # abort stuff.
  hook 'mouseup', 0, (point, event, state) ->
    # @clickedBlock and @clickedPoint should will exist iff
    # we have dragged not yet more than 5 pixels.
    #
    # To abort, all we need to do is null.
    if @clickedBlock?
      @clickedBlock = null
      @clickedPoint = null
  
  # On mousemove, if there is a clicked block but no drag block,
  # we might want to transition to a dragging the block if the user
  # moved their mouse far enough.
  hook 'mousemove', 1, (point, event, state) ->
    if not state.capturedPickup and @clickedBlock? and point.from(@clickedPoint).magnitude() > MIN_DRAG_DISTANCE

      # Signify that we are now dragging a block.
      @draggingBlock = @clickedBlock

      # Our dragging offset must be computed using the canvas on which this block
      # is rendered.
      #
      # NOTE: this really falls under "PALETTE SUPPORT", but must
      # go here. Try to organise this better.
      if @clickedBlockIsPaletteBlock
        @draggingOffset = @draggingBlock.view.bounds[@draggingBlock.view.lineStart].upperLeftCorner().from(
          @trackerPointToPalette(@clickedPoint))

        @draggingBlock = @draggingBlock.clone()
        
        # Notice that since this block effectively
        # came from nowhere, no undo operation
        # is needed to destroy it.

      else
        @draggingOffset = @draggingBlock.view.bounds[@draggingBlock.view.lineStart].upperLeftCorner().from(
          @trackerPointToMain(@clickedPoint))
        
        # Since we removed this from the tree,
        # we will need to log an undo operation
        # to put it back in.
        unless state.addedCapturePoint
          @addMicroUndoOperation 'CAPTURE_POINT'
          state.addedCapturePoint = true
        @addMicroUndoOperation new PickUpOperation @draggingBlock
      
      # Remove the block from the tree.
      @draggingBlock.moveTo null # MUTATION

      # Draw the new dragging block on the drag canvas.
      # 
      # When we are dragging things, we draw the shadow.
      # Also, we translate the block 1x1 to the right,
      # so that we can see its borders.
      @draggingBlock.view.compute(); @draggingBlock.view.translate new draw.Point 1, 1
      @draggingBlock.view.drawShadow @dragCtx, 5, 5
      @draggingBlock.view.draw @dragCtx
      
      # Translate it immediately into position
      position = new draw.Point(
        point.x + @draggingOffset.x,
        point.y + @draggingOffset.y
      )

      @dragCanvas.style.top = "#{position.y}px"
      @dragCanvas.style.left = "#{position.x}px"

      # Now we are done with the "clickedX" suite of stuff.
      @clickedPoint = @clickedBlock = null

      # Redraw the main canvas
      @redrawMain()

  # On mousemove, if there is a dragged block, we want to
  # translate the drag canvas into place,
  # as well as highlighting any focused drop areas.
  hook 'mousemove', 0, (point, event, state) ->
    if @draggingBlock?
      # Translate the drag canvas into position.
      position = new draw.Point(
        point.x + @draggingOffset.x,
        point.y + @draggingOffset.y
      )
      
      @dragCanvas.style.top = "#{position.y}px"
      @dragCanvas.style.left = "#{position.x}px"
      
      mainPoint = @trackerPointToMain(position)
      
      # If we are below the document, append to the document.
      if mainPoint.y > @tree.view.getBounds().bottom() and mainPoint.x > 0
        head = @tree.end
        until head.type is 'blockEnd' or head is @tree.start then head = head.prev
        
        if head is @tree.start then highlight = @tree
        else highlight = head.block
      
      # If we are dragging a block,
      # we can drop on any Block not in a socket,
      # any Indent, or any Socket that does
      # not contain a block.
      else if @draggingBlock.type is 'block'
        highlight = @tree.find (block) ->
          (not (block.inSocket?() ? false)) and
            block.view.dropArea? and
            block.view.dropArea.contains mainPoint
      
      # If we are dragging a segment,
      # we also cannot drop ourselves
      # into a socket.
      else if @draggingBlock.type is 'segment'
        highlight = @tree.find (block) ->
          (block.type isnt 'socket') and
            (not (block.inSocket?() ? false)) and
            block.view.dropArea? and
            block.view.dropArea.contains mainPoint

      # For performance reasons,
      # we will only redraw the main canvas
      # (and highlight the reigon) if we need
      # to to change the highlighted block.
      #
      # i.e. if nothing has changed, don't
      # redraw.
      if highlight isnt @lastHighlight
        @redrawMain()

        if highlight?
          highlight.view.dropHighlightRegion.fill @mainCtx, '#fff'

        @lastHighlight = highlight

  hook 'mouseup', 0, (point, event, state) ->
    # We will consume this event iff we dropped it successfully
    # in the root tree.
    if @draggingBlock? and @lastHighlight?
      # Depending on what the highlighted element is,
      # we might want to drop the block at its
      # beginning or at its end.
      #
      # We will need to log undo operations here too.
      switch @lastHighlight.type
        when 'indent', 'socket'
          @addMicroUndoOperation new DropOperation @draggingBlock, @lastHighlight.start
          @draggingBlock.moveTo @lastHighlight.start #MUTATION
        when 'block'
          @addMicroUndoOperation new DropOperation @draggingBlock, @lastHighlight.end
          @draggingBlock.moveTo @lastHighlight.end #MUTATION
        else
          if @lastHighlight is @tree
            @addMicroUndoOperation new DropOperation @draggingBlock, @tree.start
            @draggingBlock.moveTo @tree.start #MUTATION
      
      # Move the cursor to the position we just
      # dropped the block
      @moveCursorTo @draggingBlock.end, true

      # Now that we've done that, we can annul stuff.
      @draggingBlock = null
      @draggingOffset = null
      @lastHighlight = null
      
      @clearDrag()
      @redrawMain()

  # FLOATING BLOCK SUPPORT
  # ================================
  
  # We need to initialize the @floatingBlocks
  # array at populate-time.
  hook 'populate', 0, ->
    @floatingBlocks = []

  class FloatingBlockRecord
    constructor: (@block, @position) ->
  
  # ## Undo operations
  # We have two: FromFloating and ToFloating.
  # They mimick block move pick/drop operations
  # except that they also interact with the @floatingBlocks array.
  class ToFloatingOperation extends DropOperation
    constructor: (block, position) ->
      # Copy the position we got
      @position = new draw.Point position.x, position.y
      
      # Do all the normal blockMove stuff.
      super block, null

    undo: (editor) ->
      editor.floatingBlocks.pop()

      super

    redo: (editor) ->
      editor.floatingBlocks.push new FloatingBlockRecord @block.clone(), @position

      super

  class FromFloatingOperation
    constructor: (record) ->
      @position = new draw.Point record.position.x, record.position.y
      @block = record.block.clone()

    undo: (editor) ->
      editor.floatingBlocks.push new FloatingBlockRecord @block.clone(), @position

      return null

    redo: (editor) ->
      editor.floatingBlocks.pop()

      return null

  # We can create floating blocks by dropping
  # blocks without a highlight.
  hook 'mouseup', 0, (point, event, state) ->
    if @draggingBlock? and not @lastHighlight?
      # Before we put this block into our list of floating blocks,
      # we need to figure out where on the main canvas
      # we are going to render it.
      mainCanvasPoint = @trackerPointToMain point
      renderPoint = new draw.Point(
        mainCanvasPoint.x + @draggingOffset.x,
        mainCanvasPoint.y + @draggingOffset.y
      )
      
      # If we dropped it off in the palette, abort (so as to delete the block).
      if renderPoint.x < 0 then return
      
      # Add the undo operation associated
      # with creating this floating block
      @addMicroUndoOperation new ToFloatingOperation @draggingBlock, renderPoint

      # Add this block to our list of floating blocks
      @floatingBlocks.push new FloatingBlockRecord(
        @draggingBlock,
        renderPoint
      )
      
      # Now that we've done that, we can annul stuff.
      @draggingBlock = null
      @draggingOffset = null
      @lastHighlight = null
      
      @clearDrag()
      @redrawMain()
  
  # On mousedown, we can hit test for floating blocks.
  hook 'mousedown', 7, (point, event, state) ->
    # If someone else has already taken this click, pass.
    if state.consumedHitTest then return

    # Hit test against floating blocks
    for record, i in @floatingBlocks
      hitTestResult = hitTest @trackerPointToMain(point), record.block

      if hitTestResult?
        @clickedBlock = record.block
        @clickedPoint = point

        state.consumedHitTest = true
        
        @redrawMain()
  
  hook 'mousemove', 7, (point, event, state) ->
    if @clickedBlock? and point.from(@clickedPoint).magnitude() > MIN_DRAG_DISTANCE
      for record, i in @floatingBlocks
        if record.block is @clickedBlock
          # Add the undo operation associated
          # with picking up this floating block
          unless state.addedCapturePoint
            @addMicroUndoOperation 'CAPTURE_POINT'
            state.addedCapturePoint = true
          @addMicroUndoOperation new FromFloatingOperation record

          @floatingBlocks.splice i, 1

          @redrawMain()

          return

  # On redraw, we draw all the floating blocks
  # in their proper positions.
  hook 'redraw_main', 7, ->
    for record in @floatingBlocks
      record.block.view.compute()
      record.block.view.translate record.position

      record.block.view.draw @mainCtx

  # PALETTE SUPPORT
  # ================================

  # The first thing we will have to do with
  # the palette is install the hierarchical menu.
  #
  # This happens at population time.
  hook 'populate', 0, ->
    @currentPaletteBlocks = []
    @clickedBlockIsPaletteBlock = false
    
    # Create the hierarchical menu element.
    @paletteHeader = document.createElement 'div'
    @paletteHeader.className = 'ice-palette-header'
    
    # Record its height, which is deterministic.
    @paletteHeaderHeight = Math.ceil(@paletteGroups.length / 2) * 30

    # Append the element.
    @iceElement.appendChild @paletteHeader

    # Keep track of the row that we are on
    # in our table layout
    paletteHeaderRow = document.createElement 'div'
    paletteHeaderRow.className = 'ice-palette-header-row'

    @paletteHeader.appendChild paletteHeaderRow

    for paletteGroup, i in @paletteGroups then do (paletteGroup) =>
      # Clone all the blocks so as not to
      # intrude on outside stuff
      paletteGroup.blocks = (block.clone() for block in paletteGroup.blocks)

      # Create the element itself
      paletteGroupHeader = document.createElement 'div'
      paletteGroupHeader.className = 'ice-palette-group-header'
      paletteGroupHeader.innerText = paletteGroupHeader.textContent = paletteGroup.name # innerText and textContent for FF compatability

      paletteHeaderRow.appendChild paletteGroupHeader
      
      # Start a new row, if we're at that point
      # in our appending cycle
      if i % 2 is 1
        paletteHeaderRow = document.createElement 'div'
        paletteHeaderRow.className = 'ice-palette-header-row'
        @paletteHeader.appendChild paletteHeaderRow
      
      # When we click this element,
      # we should switch to it in the palette.
      paletteGroupHeader.addEventListener 'click', =>
        # Record that we are the selected group now
        @currentPaletteGroup = paletteGroup.name
        @currentPaletteBlocks = paletteGroup.blocks
        
        # Unapply the "selected" style to the current palette group header
        @currentPaletteGroupHeader.className = 'ice-palette-group-header'

        # Now we are the current palette group header
        @currentPaletteGroupHeader = paletteGroupHeader

        # Apply the "selected" style to us
        @currentPaletteGroupHeader.className = 'ice-palette-group-header ice-palette-group-header-selected'
        
        # Redraw the palette.
        @redrawPalette()
      
      # If we are the first element, make us the selected palette group.
      if i is 0
        @currentPaletteGroup = paletteGroup.name
        @currentPaletteBlocks = paletteGroup.blocks

        @currentPaletteGroupHeader = paletteGroupHeader

        # Apply the "selected" style to us
        @currentPaletteGroupHeader.className = 'ice-palette-group-header ice-palette-group-header-selected'

  # The palette hierarchical menu is on top of the track div
  # so that we can click it. However, we do not want this to happen
  # when we are dragging something. So:
  hook 'mousedown', 0, ->
    @paletteHeader.style.zIndex = 0

  hook 'mouseup', 0, ->
    @paletteHeader.style.zIndex = 257
  
  # The next thing we need to do with the palette
  # is let people pick things up from it.
  hook 'mousedown', 7, (point, event, state) ->
    # If someone else has already taken this click, pass.
    if state.consumedHitTest then return

    palettePoint = @trackerPointToPalette point
    for block in @currentPaletteBlocks
      hitTestResult = hitTest palettePoint, block

      if hitTestResult?
        @clickedBlock = block
        @clickedPoint = point
        @clickedBlockIsPaletteBlock = true
        return

    @clickedBlockIsPaletteBlock = false

  # We also allow people to drop things into
  # the palette to delete them.
  hook 'mouseup', 0, (point, event, state) ->
    if point.x < PALETTE_WIDTH and not @lastHighlight?
      @draggingBlock = null
      @draggingOffset = null
      @clearDrag()

  # We will also have mouseover texts for blocks.
  # This is an experimental feature right now.
  hook 'redraw_palette', 0, ->
    # Remove the existent blocks
    @paletteScrollerStuffing.innerHTML = ''

    # Add new blocks
    for block in @currentPaletteBlocks
      hoverDiv = document.createElement 'div'
      hoverDiv.className = 'ice-hover-div'

      # TODO: this should be specified by the API user
      hoverDiv.title = block.stringify()

      bounds = block.view.getBounds()

      hoverDiv.style.top = "#{bounds.y}px"
      hoverDiv.style.left = "#{bounds.x}px"

      # Clip boxes to the width of the palette to prevent x-scrolling. TODO: fix x-scrolling behaviour.
      hoverDiv.style.width = "#{Math.min(bounds.width, @paletteScroller.offsetWidth - PALETTE_LEFT_MARGIN)}px"
      hoverDiv.style.height = "#{bounds.height}px"

      @paletteScrollerStuffing.appendChild hoverDiv

  # TEXT INPUT SUPPORT
  # ================================

  # Text input has two undo events: text change
  # and text reparse.
  class TextChangeOperation extends UndoOperation
    constructor: (socket, @before) ->
      @after = socket.stringify()
      @socket = socket.start.getSerializedLocation()

    undo: (editor) ->
      socket = editor.tree.getTokenAtLocation(@socket).socket
      socket.content()?.remove()
      socket.start.insert new model.TextToken @before

    redo: (editor) ->
      socket = editor.tree.getTokenAtLocation(@socket).socket
      socket.content()?.remove()
      socket.start.insert new model.TextToken @after

  class TextReparseOperation extends UndoOperation
    constructor: (socket, @before) ->
      @after = socket.content().clone()
      @socket = socket.start.getSerializedLocation()

    undo: (editor) ->
      socket = editor.tree.getTokenAtLocation(@socket).socket
      socket.content().moveTo null
      socket.start.insert new model.TextToken @before

    redo: (editor) ->
      socket = editor.tree.getTokenAtLocation(@socket).socket
      socket.content()?.remove()
      @after.clone().moveTo socket
  
  # At populate-time, we need
  # to create and append the hidden input
  # we will use for text input.
  hook 'populate', 1, ->
    @hiddenInput = document.createElement 'input'
    @hiddenInput.className = 'ice-hidden-input'

    @iceElement.appendChild @hiddenInput

    # We also need to initialise some fields
    # for knowing what is focused
    @socketFocus = null
    @textFocus = null
    @textInputAnchor = null

    @textInputSelecting = false

    @oldFocusValue = null
    
    # The hidden input should be set up
    # to mirror the text to which it is associated.
    for event in ['input', 'keyup', 'keydown']
      @hiddenInput.addEventListener event, =>
        if @textFocus?
          @textFocus.value = @hiddenInput.value

          @redrawTextInput()

  hook 'resize', 0, ->
    @aceElement.style.width = "#{@iceElement.offsetWidth}px"
    @aceElement.style.height = "#{@iceElement.offsetHeight}px"

  # Redraw function for text input
  Editor::redrawTextInput = ->
    # Set the value in the model to fit
    # the hidden input value.
    @textFocus.value = @hiddenInput.value
    
    # Redraw the main canvas, on top of
    # which we will draw the cursor and
    # highlights.
    @redrawMain()

    # Determine the coordinate positions
    # of the typic cursor
    startPosition = @textFocus.view.bounds[@textFocus.view.lineStart].x +
      @mainCtx.measureText(@hiddenInput.value[...@hiddenInput.selectionStart]).width
    endPosition = @textFocus.view.bounds[@textFocus.view.lineStart].x +
      @mainCtx.measureText(@hiddenInput.value[...@hiddenInput.selectionEnd]).width

    # Now draw the highlight/typing cursor
    #
    # Draw a line if it is just a cursor
    if startPosition is endPosition
      @mainCtx.strokeRect startPosition, @textFocus.view.bounds[@textFocus.view.lineStart].y, 0, @fontSize

    # Draw a translucent rectangle if there is a selection.
    else
      @mainCtx.fillStyle = 'rgba(0, 0, 256, 0.3)'
      @mainCtx.fillRect startPosition, @textFocus.view.bounds[@textFocus.view.lineStart].y, endPosition - startPosition, @fontSize

  # Convenince function for setting the text input
  Editor::setTextInputFocus = (focus, selectionStart = 0, selectionEnd = 0) ->
    # If there is already a focus, we
    # need to wrap some things up with it.
    if @socketFocus? and @socketFocus isnt focus

      # The first of these is an undo operation;
      # we need to add this text change to the undo stack.
      @addMicroUndoOperation 'CAPTURE_POINT'
      @addMicroUndoOperation new TextChangeOperation @socketFocus, @oldFocusValue
      @oldFocusValue = null

      # The second of these is a reparse attempt.
      # If we can, try to reparse the focus
      # value.
      try
        newParse = coffee.parse(unparsedValue = @socketFocus.stringify()).start.next

        if newParse.type is 'blockStart'
          newParse.block.moveTo @socketFocus.start

          @addMicroUndoOperation new TextReparseOperation @socketFocus, unparsedValue

    # Now we're done with the old focus,
    # we can start over.
    #
    # Literally set the focus.
    @socketFocus = focus
    
    # If we're _unfocusing_, just do so.
    if not focus?
      @textFocus = null
      @hiddenInput.blur(); @iceElement.focus()
      return

    # Record old focus value
    @oldFocusValue = focus.stringify()

    # Now create a text token
    # with the appropriate text to put in it.
    @textFocus = new model.TextToken focus.stringify()
    focus.content()?.remove()
    focus.start.insert @textFocus
    
    # Move the cursor near this
    @moveCursorTo focus.end
    
    # Set the hidden input up to mirror the text.
    @hiddenInput.value = @textFocus.value
    
    if selectionStart < 0 then selectionStart = @textFocus.value.length - selectionStart
    if selectionEnd < 0 then selectionEnd = @textFocus.value.length - selectionEnd

    # Focus the hidden input.
    setTimeout (=>
      @hiddenInput.focus()
      @hiddenInput.setSelectionRange selectionStart, selectionEnd
    ), 0

    # Redraw.
    @redrawMain()

  # Convenience hit-testing function
  hitTestTextInput = (point, block) ->
    head = block.start
    while head?
      if head.type is 'socketStart' and head.next.type in ['text', 'socketEnd'] and
          head.socket.view.bounds[head.socket.view.lineStart].contains point
        return head.socket
      head = head.next

    return null
  
  # Convenience functions for setting
  # the text input selection, given
  # points on the main canvas.
  Editor::setTextInputAnchor = (point) ->
    @textInputAnchor = @textInputHead = Math.round(
      (point.x - @textFocus.view.bounds[@textFocus.view.lineStart].x) / @mainCtx.measureText(' ').width
    )

    @hiddenInput.setSelectionRange @textInputAnchor, @textInputHead

  Editor::setTextInputHead = (point) ->
    @textInputHead = Math.round(
      (point.x - @textFocus.view.bounds[@textFocus.view.lineStart].x) / @mainCtx.measureText(' ').width
    )

    @hiddenInput.setSelectionRange Math.min(@textInputAnchor, @textInputHead), Math.max(@textInputAnchor, @textInputHead)
  
  # On mousedown, we will want to start
  # selections and focus text inputs
  # if we apply.
  hook 'mousedown', 6, (point, event, state) ->
    # If someone else already took this click, return.
    if state.consumedHitTest then return
    
    # Otherwise, look for a socket that
    # the user has clicked
    mainPoint = @trackerPointToMain point
    hitTestResult = hitTestTextInput mainPoint, @tree
    
    # If they have clicked a socket,
    # focus it, and 
    if hitTestResult?
      @setTextInputFocus hitTestResult

      setTimeout (=>
        @setTextInputAnchor mainPoint
        @redrawTextInput()

        @textInputSelecting = true
      ), 0

      state.consumedHitTest = true
  
  # On mousemove, if we are selecting,
  # we want to update the selection
  # to match the mouse.
  hook 'mousemove', 0, (point, event, state) ->
    if @textInputSelecting
      mainPoint = @trackerPointToMain point

      @setTextInputHead mainPoint

      @redrawTextInput()
  
  # On mouseup, we want to stop selecting.
  hook 'mouseup', 0, (point, event, state) ->
    @textInputSelecting = false

  # LASSO SELECT SUPPORT
  # ================================
  
  # We need undo operations for create/destroy segment
  # so that other undo operations work properly in
  # the tree -- for instance, DropOperation needs
  # to have the segment in the tree that is being
  # dropped in order to work.
  class CreateSegmentOperation extends UndoOperation
    constructor: (segment) ->
      @first = segment.start.getSerializedLocation()
      @last = segment.end.getSerializedLocation()
      @lassoSelect = segment.isLassoSelect

    undo: (editor) ->
      editor.tree.getTokenAtLocation(@first).segment.remove()

      return editor.tree.getTokenAtLocation @first

    redo: (editor) ->
      segment = new model.Segment()
      segment.lassoSelect = @lassoSelect
      editor.tree.getTokenAtLocation(@first).insertBefore segment.start
      editor.tree.getTokenAtLocation(@last).insertBefore segment.end

      return segment.end

  class DestroySegmentOperation extends UndoOperation
    constructor: (segment) ->
      @first = segment.start.getSerializedLocation()
      @last = segment.end.getSerializedLocation()
      @lassoSelect = segment.isLassoSelect

    undo: (editor) ->
      segment = new model.Segment()
      segment.lassoSelect = @lassoSelect
      editor.tree.getTokenAtLocation(@first).insertBefore segment.start
      editor.tree.getTokenAtLocation(@last).insertBefore segment.end

      return segment.end

    redo: (editor) ->
      editor.tree.getTokenAtLocation(@first).segment.remove()

      return editor.tree.getTokenAtLocation @first

  # The lasso select
  # will have its own canvas
  # for drawing the lasso. This needs
  # to be added at populate-time, along
  # with some fields.
  hook 'populate', 0, ->
    @lassoSelectCanvas = document.createElement 'canvas'
    @lassoSelectCanvas.className = 'ice-lasso-select-canvas'

    @lassoSelectCtx = @lassoSelectCanvas.getContext '2d'

    @lassoSelectAnchor = null
    @lassoSegment = null

    @iceElement.appendChild @lassoSelectCanvas
  
  # Conveneince function for clearing
  # the lasso select canvas
  Editor::clearLassoSelectCanvas = ->
    @lassoSelectCtx.clearRect 0, 0, @lassoSelectCanvas.width, @lassoSelectCanvas.height
  
  # Deal with resize for the lasso
  # select canvas
  hook 'resize', 0, ->
    @lassoSelectCanvas.width = @iceElement.offsetWidth - PALETTE_WIDTH
    @lassoSelectCanvas.style.width = "#{@lassoSelectCanvas.width}px"

    @lassoSelectCanvas.height = @iceElement.offsetHeight
    @lassoSelectCanvas.style.height = "#{@lassoSelectCanvas.height}px"

  Editor::clearLassoSelection = ->
    @lassoSegment = null

    head = @tree.start
    needToRedraw = false
    until head is @tree.end
      if head.type is 'segmentStart' and head.segment.isLassoSegment
        next = head.next
        
        @addMicroUndoOperation new DestroySegmentOperation head.segment
        head.segment.remove() #MUTATION
        needToRedraw = true
        
        head = next

      else
        head = head.next

    if needToRedraw then @redrawMain()
  
  # On mousedown, if nobody has taken
  # a hit test yet, start a lasso select.
  hook 'mousedown', 0, (point, event, state) ->
    # Even if someone has taken it, we
    # should remove the lasso segment that is
    # already there.
    unless state.clickedLassoSegment then @clearLassoSelection()
    
    if state.consumedHitTest then return
    
    # If the point was actually in the main canvas,
    # start a lasso select.
    if point.x > PALETTE_WIDTH
      @lassoSelectAnchor = @trackerPointToMain point
  
  # On mousemove, if we are in the middle of a
  # lasso select, continue with it.
  hook 'mousemove', 0, (point, event, state) ->
    if @lassoSelectAnchor?
      mainPoint = @trackerPointToMain point

      @clearLassoSelectCanvas()
      
      # (draw the lasso rectangle)
      topLeftCorner = new draw.Point(
        Math.min(@lassoSelectAnchor.x, mainPoint.x) - @scrollOffsets.main.x,
        Math.min(@lassoSelectAnchor.y, mainPoint.y) - @scrollOffsets.main.y
      )

      size = new draw.Size(
        Math.abs(@lassoSelectAnchor.x - mainPoint.x),
        Math.abs(@lassoSelectAnchor.y - mainPoint.y)
      )
      
      @lassoSelectCtx.strokeStyle = '#00f'
      @lassoSelectCtx.strokeRect topLeftCorner.x, topLeftCorner.y, size.width, size.height
  
  # Convnience function for validating
  # a lasso selection. A lasso selection
  # cannot contain start tokens without
  # their corresponding end tokens, or vice
  # versa, and also must start and end
  # with blocks (not Indents).
  validateLassoSelection = (tree, first, last) ->
    tokensToInclude = []
    head = first
    until head is last.next
      switch head.type
        when 'blockStart', 'blockEnd'
          tokensToInclude.push head.block.start
          tokensToInclude.push head.block.end
        when 'indentStart', 'indentEnd'
          tokensToInclude.push head.indent.start
          tokensToInclude.push head.indent.end
        when 'segmentStart', 'segmentEnd'
          tokensToInclude.push head.segment.start
          tokensToInclude.push head.segment.end
      head = head.next
    
    first = tree.start
    until first in tokensToInclude then first = first.next

    last = tree.end
    until last in tokensToInclude then last = last.prev

    until first.type is 'blockStart'
      first = first.prev
      if first.type is 'blockEnd' then first = first.block.start.prev

    until last.type is 'blockEnd'
      last = last.next
      if last.type is 'blockStart' then last = last.block.end.next

    return [first, last]
  
  # On mouseup, if we were
  # doing a lasso select, insert a lasso
  # select segment.
  hook 'mouseup', 0, (point, event, state) ->
    if @lassoSelectAnchor?
      mainPoint = @trackerPointToMain point
      lassoRectangle = new draw.Rectangle(
          Math.min(@lassoSelectAnchor.x, mainPoint.x),
          Math.min(@lassoSelectAnchor.y, mainPoint.y),
          Math.abs(@lassoSelectAnchor.x - mainPoint.x),
          Math.abs(@lassoSelectAnchor.y - mainPoint.y)
      )

      @lassoSelectAnchor = null
      @clearLassoSelectCanvas()
      
      first = @tree.start
      until (not first?) or first.type is 'blockStart' and first.block.view.path.intersects lassoRectangle
        first = first.next

      last = @tree.end
      until (not last?) or last.type is 'blockEnd' and last.block.view.path.intersects lassoRectangle
        last = last.prev

      unless first? and last? then return

      [first, last] = validateLassoSelection @tree, first, last

      @lassoSegment = new model.Segment()
      @lassoSegment.isLassoSegment = true
      
      first.insertBefore @lassoSegment.start #MUTATION
      last.insert @lassoSegment.end #MUTATION

      @addMicroUndoOperation new CreateSegmentOperation @lassoSegment
      
      # Move the cursor to the segment we just created
      @moveCursorTo @lassoSegment.end, true

      @redrawMain()
  
  # On mousedown, we might want to 
  # pick a selected segment up; check.
  hook 'mousedown', 6.5, (point, event, state) ->
    if state.consumedHitTest then return

    if @lassoSegment? and hitTest(@trackerPointToMain(point), @lassoSegment)?
      @clickedBlock = @lassoSegment
      @clickedPoint = point

      state.consumedHitTest = true
      state.clickedLassoSegment = true

  # CURSOR OPERATION SUPPORT
  # ================================
  
  hook 'populate', 0, ->
    @cursor = new model.CursorToken()
  
  # A cursor cannot be inside only a block.
  # Convenience function for this validation:
  isValidCursorPosition = (pos) ->
    depth = 0
    until depth is 0 and pos.type in ['blockStart', 'indentStart'] or not pos.prev?
      switch pos.type
        when 'blockStart', 'indentStart', 'socketStart' then depth--
        when 'blockEnd', 'indentEnd', 'socketEnd' then depth++
      pos = pos.prev
    
    return pos.type is 'indentStart' or not pos.prev?

  # A cursor is only allowed to be on a line.
  Editor::moveCursorTo = (destination, attemptReparse = false) ->
    # If the destination is not inside the tree,
    # abort.
    unless destination? then return
    head = destination; until head in [null, @tree.end] then head = head.next
    unless head? then return
    
    # Otherwise, splice the cursor out.
    @cursor.remove()
    
    # If the destination is in the tree,
    # figure out where we want to place the cursor.

    # We can place the cursor
    # at the start of the tree
    if destination is @tree.start
      destination.insert @cursor
    
    # If we got some other token,
    # scan forward until we find
    # a viable spot for the cursor.
    else
      head = destination
      until head.type in ['newline', 'indentEnd'] or head is @tree.end
        head = head.next

      if head.type is 'newline' then head.insert @cursor
      else head.insertBefore @cursor
    
    # Keep scanning forward if this is an improper location.
    unless isValidCursorPosition @cursor then @moveCursorTo @cursor.next

    if attemptReparse
      @reparseHandwrittenBlocks()

    @redrawMain()
  
  Editor::moveCursorUp = ->
    # Seek the place we want to move the cursor
    head = @cursor.prev?.prev
    
    # If we're at the beginning, abort.
    unless head? then return

    until head.type in ['newline', 'indentEnd'] or head is @tree.start
      head = head.prev
    
    # Splice out
    @cursor.remove()
  
    # Splice in
    if head.type is 'newline' or head is @tree.start then head.insert @cursor
    else head.insertBefore @cursor
    
    # Keep sacnning backwards if this is an improper location.
    unless isValidCursorPosition @cursor then @moveCursorUp()
    
    @reparseHandwrittenBlocks()
    @redrawMain()

  # Pressing the up-arrow moves the cursor up.
  hook 'key.up', 0, ->
    @clearLassoSelection()
    @setTextInputFocus null
    @moveCursorUp()
  
  # Pressing the down-arrow moves the cursor down.
  hook 'key.down', 0, ->
    @clearLassoSelection()
    @setTextInputFocus null
    @reparseHandwrittenBlocks()
    @moveCursorTo @cursor.next.next

  hook 'key.left', 0, ->
    if @socketFocus?
      if @hiddenInput.selectionEnd is 0
        head = @socketFocus.start

      else return

    else
      head = @cursor

    until (not head?) or head.type is 'socketEnd' and head.socket.content().type is 'text'
      head = head.prev

    if head?
      @setTextInputFocus head.socket, -1, -1

  hook 'key.right', 0, ->
    if @socketFocus?
      if @hiddenInput.selectionEnd is @hiddenInput.value.length
        head = @socketFocus.end

      else return

    else
      head = @cursor

    until (not head?) or head.type is 'socketStart' and head.socket.content().type is 'text'
      head = head.next

    if head?
      @setTextInputFocus head.socket
  
  Editor::deleteAtCursor = ->
    # Unfocus any inputs, which could get in the way.
    @setTextInputFocus null

    blockEnd = @cursor.prev

    until blockEnd.type in ['blockEnd', 'indentStart']
      blockEnd = blockEnd.prev

    if blockEnd.type is 'blockEnd'
      @addMicroUndoOperation 'CAPTURE_POINT'
      @addMicroUndoOperation new PickUpOperation blockEnd.block

      blockEnd.block.moveTo null #MUTATION

      @redrawMain()

  hook 'key.backspace', 0, (state) ->
    if state.capturedBackspace then return

    # We don't want to interrupt any text input editing
    # sessions. We will, however, delete a handwritten
    # block if it is currently empty.
    if not @textFocus? or
        (@hiddenInput.value.length is 0 and @socketFocus.handwritten)
      @deleteAtCursor()
      state.capturedBackspace = true
      return false

    return true

  # HANDWRITTEN BLOCK SUPPORT
  # ================================
  
  hook 'populate', 0, ->
    @handwrittenBlocks = []

  hook 'key.enter', 0, ->
    @setTextInputFocus null
    
    # Construct the block; flag the socket as handwritten
    newBlock = new model.Block(); newSocket = new model.Socket null, -Infinity
    newBlock.start.insert newSocket.start; newBlock.end.prev.insert newSocket.end
    newSocket.handwritten = true

    # Add it io our list of handwritten blocks
    @handwrittenBlocks.push newBlock
    
    # Seek a place near the cursor we can actually
    # put a block.
    head = @cursor.prev
    while head.type in ['newline', 'cursor', 'segmentStart', 'segmentEnd'] and head isnt @tree.start
      head = head.prev
    
    # Log the undo operation for this
    @addMicroUndoOperation 'CAPTURE_POINT'
    @addMicroUndoOperation new DropOperation newBlock, head

    newBlock.moveTo head #MUTATION

    @redrawMain()
    @reparseHandwrittenBlocks()
    @setTextInputFocus newSocket
  
  containsCursor = (block) ->
    head = block.start
    until head is block.end
      if head.type is 'cursor' then return true
      head = head.next

    return false
  
  # The Reparse undo operation.
  class ReparseOperation extends UndoOperation
    constructor: (block, parse) ->
      @before = block.clone()
      @location = block.start.getSerializedLocation()
      @after = parse.clone()

    undo: (editor) ->
      block = editor.tree.getTokenAtLocation(@location).block
      newBlock = @before.clone()
      block.start.prev.append newBlock.start
      newBlock.end.append block.end.next

    redo: (editor) ->
      block = editor.tree.getTokenAtLocation(@location).block
      newBlock = @after.clone()
      block.prev.append newBlock.start
      newBlock.end.append block.end.next

  Editor::reparseHandwrittenBlocks = ->
    @setTextInputFocus null

    # Scan through the document to find handwritten
    # blocks
    head = @tree.start
    until head is @tree.end
      # If this is the start of a handwritten block,
      # we may want to reparse it.
      if  head.type is 'blockStart' and
          head.next.type is 'socketStart' and
          head.next.socket.handwritten and
          not containsCursor head.block
        try
          # Reparse the block.
          newBlock = coffee.parse(head.block.stringify()).start.next

          # (we only reparse if it is actually
          # a better parse than a handwritten block).
          if newBlock.type is 'blockStart'
            # Log the undo operation
            @addMicroUndoOperation new ReparseOperation head.block, newBlock.block

            # Splice it in perfectly.
            head.prev.append newBlock
            newBlock.block.end.append head.block.end.next
            
            head = newBlock.block.end

      head = head.next

    return null

  # INDENT CREATE/DESTROY SUPPORT
  # ================================
  
  # CreateIndent undo operation
  class CreateIndentOperation extends UndoOperation
    constructor: (pos, @depth) ->
      @location = pos.getSerializedLocation()
    
    undo: (editor) ->
      indent = editor.tree.getTokenAtLocation(@location).indent
      indent.start.prev.append indent.end.next

    redo: (editor) ->
      head = editor.tree.getTokenAtLocation(@location)

      newIndent = new model.Indent DEFAULT_INDENT_DEPTH
      head.prev.append(newIndent.start)
               .append(new model.NewlineToken())
               .append(newIndent.end)
               .append(head)
  
  # DestroyIndent undo operation
  class DestroyIndentOperation extends UndoOperation
    constructor: (indent) ->
      @location = indent.start.getSerializedLocation()
      @indent = indent.clone()
    
    undo: (editor) ->
      head = editor.tree.getTokenAtLocation(@location)

      newIndent = @indent.clone()
      head.prev.append(newIndent.start)
      newIndent.end.append head

    redo: (editor) ->
      indent = editor.tree.getTokenAtLocation(@location).indent
      indent.start.prev.append indent.end.next

  # If we press tab while we are editing
  # a handwritten block, we create and indent.
  hook 'key.tab', 0, ->
    if @socketFocus? and @socketFocus.handwritten
      @addMicroUndoOperation 'CAPTURE_POINT'

      # Seek the block directly before this
      head = @socketFocus.start
      until head.type is 'blockEnd'
        head = head.prev
      
      # If it ends in an indent,
      # move this block to that indent.
      if head.prev.type is 'indentEnd'
        until head.type in ['blockEnd', 'indentStart']
          head = head.prev
      
      # Otherwise, create an indent right before this.
      else
        @addMicroUndoOperation new CreateIndentOperation head, DEFAULT_INDENT_DEPTH

        newIndent = new model.Indent DEFAULT_INDENT_DEPTH
        head.prev.append(newIndent.start) #MUTATION
                 .append(new model.NewlineToken())
                 .append(newIndent.end)
                 .append(head)
        
        head = newIndent.start

      # Go through the motions of moving this block into
      # the indent we have just found.
      @addMicroUndoOperation new PickUpOperation @socketFocus.start.prev.block
      @socketFocus.start.prev.block.moveTo null #MUTATION

      @addMicroUndoOperation new DropOperation @socketFocus.start.prev.block, head
      @socketFocus.start.prev.block.moveTo head #MUTATION
      
      # Move the cursor up to where the block now is.
      @moveCursorTo @socketFocus.start.prev.block.end
      
      @redrawMain()

  # If we press backspace at the start of an empty
  # indent (an indent containing only whitespace),
  # delete that indent.
  hook 'key.backspace', 0, (state) ->
    if state.capturedBackspace then return

    if  not @socketFocus? and
        @cursor.prev?.prev?.type is 'indentStart' and
        (indent = @cursor.prev.prev.indent).stringify().trim().length is 0

      @addMicroUndoOperation new DestroyIndentOperation indent
      indent.start.prev.append indent.end.next #MUTATION
      
      @moveCursorTo indent.end.next

      state.capturedBackspace = true
      
      @redrawMain()

  # ANIMATION AND ACE EDITOR SUPPORT
  # ================================
  
  hook 'populate', 0, ->
    @aceElement = document.createElement 'div'
    @aceElement.className = 'ice-ace'

    @wrapperElement.appendChild @aceElement

    @aceEditor = ace.edit @aceElement

    @aceEditor.setTheme 'ace/theme/chrome'
    @aceEditor.setFontSize 15
    @aceEditor.getSession().setMode 'ace/mode/coffee'
    @aceEditor.getSession().setTabSize 2

    @aceEditor.on 'change', =>
      @setFontSize @aceEditor.getFontSize()

    @currentlyUsingBlocks = true
    @currentlyAnimating = false
  
  # For animation and ace editor,
  # we will need a couple convenience functions
  # for getting the "absolute"-esque position
  # of layouted elements (a la jQuery, without jQuery).
  getOffsetTop = (element) ->
    top = element.offsetTop

    while (element = element.offsetParent)?
      top += element.offsetTop

    return top
  
  getOffsetLeft = (element) ->
    left = element.offsetLeft

    while (element = element.offsetParent)?
      left += element.offsetLeft

    return left

  Editor::computePlaintextTranslationVectors = ->
    # Now we need to figure out where all the text elements are going
    # to end up.
    textElements = []; translationVectors = []

    head = @tree.start

    state = {
      # Initial cursor positions are
      # determined by ACE editor configuration.
      x: (@aceEditor.container.getBoundingClientRect().left -
          getOffsetLeft(@aceElement) +
          @aceEditor.renderer.$gutterLayer.gutterWidth)
      y: (@aceEditor.container.getBoundingClientRect().top -
          getOffsetTop(@aceElement))

      # Initial indent depth is 0
      indent: 0

      # Line height and left edge are
      # determined by ACE editor configuration.
      lineHeight: @aceEditor.renderer.layerConfig.lineHeight
      leftEdge: (@aceEditor.container.getBoundingClientRect().left -
          getOffsetLeft(@aceElement) +
          @aceEditor.renderer.$gutterLayer.gutterWidth)
    }

    until head is @tree.end
      switch head.type
        when 'text'
          translationVectors.push head.view.computePlaintextTranslationVector state, @mainCtx
          textElements.push head

        # Newline moves the cursor to the next line,
        # plus some indent.
        when 'newline'
          state.y += state.lineHeight
          state.x = state.indent * @mainCtx.measureText(' ').width + state.leftEdge
        
        when 'indentStart'
          state.indent += head.indent.depth

        when 'indentEnd'
          state.indent -= head.indent.depth

      head = head.next

    return {
      textElements: textElements
      translationVectors: translationVectors
    }
  
  class AnimatedColor
    constructor: (@start, @end, @time) ->
      @currentRGB = [
        parseInt(@start[1...3], 16)
        parseInt(@start[3...5], 16)
        parseInt(@start[5...7], 16)
      ]

      @step = [
        (parseInt(@end[1...3], 16) - @currentRGB[0]) / @time
        (parseInt(@end[3...5], 16) - @currentRGB[1]) / @time
        (parseInt(@end[5...7], 16) - @currentRGB[2]) / @time
      ]

    advance: ->
      for item, i in @currentRGB
        @currentRGB[i] += @step[i]

      return "rgb(#{Math.round(@currentRGB[0])},#{Math.round(@currentRGB[1])},#{Math.round(@currentRGB[2])})"

  Editor::performMeltAnimation = ->
    if @currentlyUsingBlocks and not @currentlyAnimating
      @currentlyUsingBlocks = false
      @currentlyAnimating = true

      @redrawMain()

      @aceEditor.setValue @getValue(), -1

      # Move the palette header into the background
      @paletteHeader.style.zIndex = 0

      # Compute where the text will end up
      # in the ace editor
      {textElements, translationVectors} = @computePlaintextTranslationVectors()
      animatedColor = new AnimatedColor '#CCCCCC', '#FFFFFF', ANIMATION_FRAME_RATE

      originalOffset = @scrollOffsets.main.y
      
      tick = (count) =>
        # Schedule the next animation frame
        # right away
        if count < ANIMATION_FRAME_RATE
          setTimeout (->
            tick count + 1
          ), 1000 / ANIMATION_FRAME_RATE
        
        # Fade away the blocks
        @mainCtx.globalAlpha = Math.max 0, 1 - 2 * count / ANIMATION_FRAME_RATE
        
        # Animate the main canvas color
        @iceElement.style.backgroundColor =
          @mainCanvas.style.backgroundColor = animatedColor.advance()

        @mainCanvas.style.left = "#{PALETTE_WIDTH * (1 - count / ANIMATION_FRAME_RATE)}px"
        @paletteCanvas.style.opacity =
          @paletteHeader.style.opacity = Math.max 0, 1 - 2 * (count / ANIMATION_FRAME_RATE)

        @clearMain()
        
        # Scroll the document to root position
        # (so as to line up with ACE editor)
        @mainCtx.translate 0, originalOffset / ANIMATION_FRAME_RATE
        @scrollOffsets.main.y -= originalOffset / ANIMATION_FRAME_RATE
        
        # Redraw the tree (fading)
        @tree.view.draw @mainCtx
        
        # Redraw all the text elements in animation
        @mainCtx.globalAlpha = 1

        for element, i in textElements
          element.view.textElement.draw @mainCtx
          element.view.translate new draw.Point(
            translationVectors[i].x / ANIMATION_FRAME_RATE,
            translationVectors[i].y / ANIMATION_FRAME_RATE
          )

        # Simultaneously, we will animate
        # the canvas to the left, and fade 

        if count is ANIMATION_FRAME_RATE
          # Translate the ICE editor div out of frame.
          @iceElement.style.top = "-9999px"
          @iceElement.style.left = "-9999px"
          
          # Translate the ACE editor div into frame.
          @aceElement.style.top = "0px"
          @aceElement.style.left = "0px"
          
          # Finalize a bunch of animations
          # that should be complete by now,
          # but might not actually be due to
          # floating point stuff.
          @currentlyAnimating = false
          @scrollOffsets.main.y = 0
          @mainCtx.setTransform 1, 0, 0, 1, 0, 0

      tick 0

      return success: true

  Editor::performFreezeAnimation = ->
    if not @currentlyUsingBlocks and not @currentlyAnimating
      setValueResult = @setValue @aceEditor.getValue()

      unless setValueResult.success
        return setValueResult

      @setFontSize @aceEditor.getFontSize()
      @redrawMain()

      @currentlyUsingBlocks = true
      @currentlyAnimating = true
      console.log 'set OFF'

      @aceElement.style.top = "-9999px"
      @aceElement.style.left = "-9999px"

      @iceElement.style.top = "0px"
      @iceElement.style.left = "0px"

      @paletteHeader.style.zIndex = 0

      {textElements, translationVectors} = @computePlaintextTranslationVectors()

      for element, i in textElements
        element.view.translate translationVectors[i]

      animatedColor = new AnimatedColor '#FFFFFF', '#CCCCCC', ANIMATION_FRAME_RATE

      tick = (count) =>
        if count < ANIMATION_FRAME_RATE
          setTimeout (->
            tick count + 1
          ), 1000 / ANIMATION_FRAME_RATE
        
        @mainCanvas.style.left = "#{PALETTE_WIDTH * (count / ANIMATION_FRAME_RATE)}px"
        @iceElement.style.backgroundColor =
          @mainCanvas.style.backgroundColor = animatedColor.advance()
        @paletteCanvas.style.opacity =
          @paletteHeader.style.opacity = Math.max 0, 1 - 2 * (1 - count / ANIMATION_FRAME_RATE)
        
        @clearMain()
        
        @mainCtx.globalAlpha = Math.max 0, 1 - 2 * (1 - count / ANIMATION_FRAME_RATE)
        
        @tree.view.draw @mainCtx
        
        @mainCtx.globalAlpha = 1
        
        for element, i in textElements
          element.view.textElement.draw @mainCtx
          element.view.translate new draw.Point(
            -translationVectors[i].x / ANIMATION_FRAME_RATE,
            -translationVectors[i].y / ANIMATION_FRAME_RATE
          )
        
        if count is ANIMATION_FRAME_RATE
          @currentlyAnimating = false
          @redrawMain()
          @paletteHeader.style.zIndex = 257

      tick 0

      return success: true

  Editor::toggleBlocks = ->
    console.log @currentlyAnimating
    if @currentlyUsingBlocks
      return @performMeltAnimation()
    else
      return @performFreezeAnimation()

  # SCROLLING SUPPORT
  # ================================

  hook 'populate', 0, ->
    @scrollOffsets = {
      main: new draw.Point 0, 0
      palette: new draw.Point 0, 0
    }
    
    @mainScroller = document.createElement 'div'
    @mainScroller.className = 'ice-main-scroller'

    @mainScrollerStuffing = document.createElement 'div'
    @mainScrollerStuffing.className = 'ice-main-scroller-stuffing'

    @mainScroller.appendChild @mainScrollerStuffing
    @tracker.appendChild @mainScroller

    @mainScroller.addEventListener 'scroll', =>
      @scrollOffsets.main.y = @mainScroller.scrollTop
      @scrollOffsets.main.x = @mainScroller.scrollLeft

      @mainCtx.setTransform 1, 0, 0, 1, -@scrollOffsets.main.x, -@scrollOffsets.main.y

      @redrawMain()

    @paletteScroller = document.createElement 'div'
    @paletteScroller.className = 'ice-palette-scroller'

    @paletteScrollerStuffing = document.createElement 'div'
    @paletteScrollerStuffing.className = 'ice-palette-scroller-stuffing'

    @paletteScroller.appendChild @paletteScrollerStuffing
    @tracker.appendChild @paletteScroller

    @paletteScroller.addEventListener 'scroll', =>
      @scrollOffsets.palette.y = @paletteScroller.scrollTop

      # Temporarily ignoring x-scroll to fix bad x-scrolling behaviour
      # when dragging blocks out of the palette. TODO: fix x-scrolling behaviour.
      #@scrollOffsets.palette.x = @paletteScroller.scrollLeft

      @paletteCtx.setTransform 1, 0, 0, 1, -@scrollOffsets.palette.x, -@scrollOffsets.palette.y

      @redrawPalette()
  
  hook 'resize', 0, ->
    @mainScroller.style.width = "#{@iceElement.offsetWidth - PALETTE_WIDTH}px"
    @mainScroller.style.height = "#{@iceElement.offsetHeight}px"
    
    @paletteScroller.style.top = "#{@paletteHeaderHeight}px"
    @paletteScroller.style.width = "#{PALETTE_WIDTH}px"
    @paletteScroller.style.height = "#{@iceElement.offsetHeight - @paletteHeaderHeight}px"

  hook 'redraw_main', 0, ->
    bounds = @tree.view.getBounds()
    for record in @floatingBlocks
      bounds.unite record.block.view.getBounds()

    @mainScrollerStuffing.style.width = "#{bounds.right()}px"
    @mainScrollerStuffing.style.height = "#{bounds.bottom()}px"

  hook 'redraw_palette', 0, ->
    bounds = new draw.NoRectangle()
    for block in @currentPaletteBlocks
      bounds.unite block.view.getBounds()
    
    # For now, we will comment out this line
    # due to bugs
    #@paletteScrollerStuffing.style.width = "#{bounds.right()}px"
    @paletteScrollerStuffing.style.height = "#{bounds.bottom()}px"

  # MULTIPLE FONT SIZE SUPPORT
  # ================================
  hook 'populate', 0, ->
    @fontSize = 15

  Editor::setFontSize = (fontSize) ->
    @fontSize = fontSize
    @paletteHeader.style.fontSize = "#{fontSize}px"
    @redrawMain(); @redrawPalette()

  # MUTATION BUTTON SUPPORT
  # ================================

  class MutationButtonOperation extends UndoOperation
    constructor: (button) ->
      @button = button.clone()
      @location = button.getSerializedLocation()
      
    undo: (editor) ->
      end = start = editor.tree.getTokenAtLocation(@location)
      
      # We want to scan (n) tokens forward, where
      # (n) is the length of the expanded value
      # of this token.
      head = @button.expandValue.start.next
      until head is @button.expandValue.end
        head = head.next; end = end.next
      
      # Splice the original button in.
      start.prev.append(button = @button.clone()).append end
      
      return button
      
    redo: (editor) ->
      editor.tree.getTokenAtLocation(@location).expand()
      
  hook 'mousedown', 6.9, (point, event, state) ->
    if state.consumedHitTest then return
    
    mainPoint = @trackerPointToMain point

    head = @tree.start
    until head is @tree.end
      if head.type is 'mutationButton' and head.view.bounds[head.view.lineStart].contains mainPoint
        @addMicroUndoOperation new MutationButtonOperation head
        head.expand() #MUTATION
        
        @redrawMain()
        state.consumedHitTest = true

        return

      head = head.next

  # LINE MARKING SUPPORT
  # ================================

  Editor::markLine = (line, style) ->
    @tree.getBlockOnLine(line)?.lineMarkStyles.push style

    @redrawMain()

  Editor::unmarkLine = (line, tag) ->
    unless (blockOnLine = @tree.getBlockOnLine(line))? then return

    for style, i in blockOnLine.lineMarkStyles
      if style.tag is tag
        blockOnLine.lineMarkStyles.splice i, 1
        break

    @redrawMain()

  Editor::clearLineMarks = (tag) ->
    head = @tree.start

    until head is @tree.end
      if head.type is 'blockStart'
        # If clearLineMarks is called without
        # a tag to clear, clear all tags.
        unless tag?
          head.block.lineMarkStyles.length = 0

        # Otherwise, clear the selected tag.
        else
          for style, i in head.block.lineMarkStyles
            if style.tag is tag
              head.block.lineMarkStyles.splice i, 1
              break

      head = head.next

    @redrawMain()

  # LINE HOVER SUPPORT
  # ================================

  hook 'populate', 0, ->
    @lastHoveredLine = null
  
  hook 'mousemove', 0, (point, event, state) ->
    # Do not attempt to detect this if we are currently dragging something,
    # or no event handlers are bound.
    if not @draggingBlock? and not @clickedBlock? and @hasEvent 'linehover'
      mainPoint = @trackerPointToMain point
      
      # Brute force find the hovered line
      for line in [@tree.view.lineStart..@tree.view.lineEnd]
        if @tree.view.bounds[line].contains mainPoint
          # If the hovered line _changed_, fire the event
          if line isnt @lastHoveredLine then @fireEvent 'linehover', [line: line]
          @lastHoveredLine = line
          return
      
      # Fire the event with line: null if there was no hovered line,
      # but again only if this is news.
      if @lastHoveredLine isnt null then @fireEvent 'linehover', [line: null]
      @lastHoveredLine = null

  # GET/SET VALUE SUPPORT
  # ================================

  class SetValueOperation extends UndoOperation
    constructor: (@oldValue, @newValue) ->

    undo: (editor) ->
      editor.tree = @oldValue.clone()

      return editor.tree.start
    
    redo: (editor) ->
      editor.tree = @newValue.clone()

      return editor.tree.start
  
  # Whitespace trimming hack enable/disable
  # setter
  hook 'populate', 0, ->
    @trimWhitespace = false

  Editor::setTrimWhitespace = (trimWhitespace) ->
    @trimWhitespace = trimWhitespace

  Editor::setValue = (value) ->
    try
      # Whitespace trimming hack to account
      # for ACE editor extra line in some applications
      if @trimWhitespace then value = value.trim()

      newParse = coffee.parse value
      
      if value isnt @tree.stringify()
        @addMicroUndoOperation 'CAPTURE_POINT'
      @addMicroUndoOperation new SetValueOperation @tree, newParse
      
      @tree = newParse
      @tree.start.insert @cursor
      @redrawMain()

      return success: true

    catch e
      return success: false, error: e

  Editor::getValue = -> @tree.stringify()
  
  # PUBLIC EVENT BINDING HOOKS
  # ===============================
  
  hook 'populate', 0, ->
    @bindings = {}

  Editor::on = (event, handler) ->
    @bindings[event] = handler

  Editor::once = (event, handler) ->
    @bindings[event] = ->
      handler.apply this, arguments
      @bindings[event] = null
  
  Editor::fireEvent = (event, args) ->
    if event of @bindings
      @bindings[event].apply this, args

  Editor::hasEvent = (event) -> event of @bindings and @bindings[event]?

  # SYNCHRONOUS TOGGLE SUPPORT
  # ================================

  Editor::setEditorState = (useBlocks) ->
    if useBlocks
      @setValue @aceEditor.getValue()

      @iceElement.style.top = @iceElement.style.left = '0px'
      @aceElement.style.top = @aceElement.style.left = '-9999px'
      @currentlyUsingBlocks = true

      @resize(); @redrawMain()

    else
      @aceEditor.setValue @getValue(), -1

      @iceElement.style.top = @iceElement.style.left = '-9999px'
      @aceElement.style.top = @aceElement.style.left = '0px'
      @currentlyUsingBlocks = false

      @resize()

  # DRAG CANVAS SHOW/HIDE HACK
  # ================================
  
  # On mousedown, bring the drag
  # canvas to the front so that it
  # appears to "float" over all other elements
  hook 'mousedown', 0, ->
    @dragCanvas.style.zIndex = 300
  
  # On mouseup, throw the drag canvas away completely.
  hook 'mouseup', 0, ->
    @dragCanvas.style.top =
      @dragCanvas.style.left = '-9999px'

    @dragCanvas.style.zIndex = 0
  
  # CLOSING FOUNDATIONAL STUFF
  # ================================

  # Order the arrays correctly.
  for key of unsortedEditorBindings
    unsortedEditorBindings[key].sort (a, b) -> if a.priority > b.priority then -1 else 1
    
    editorBindings[key] = []

    for binding in unsortedEditorBindings[key]
      editorBindings[key].push binding.fn
  
  editorBindings.key = {}

  for key of unsortedEditorKeyBindings
    unsortedEditorKeyBindings[key].sort (a, b) -> if a.priority > b.priority then -1 else 1
    
    editorBindings.key[key] = []

    for binding in unsortedEditorKeyBindings[key]
      editorBindings.key[key].push binding.fn
    
  return exports