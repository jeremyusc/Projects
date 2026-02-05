class packet_base_trans_c extends uvm_sequence_item;

  // Constructor: pass the name to the base class
  function new(string name = "");
    super.new(name);
  endfunction

  // Transaction ID Control, used by Scoreboard in case necessary
  // Add rand, because data will also used by driver
  rand int packet_length;   // total number of transactions, usually
                            // last index should equal to this number - 1

  rand int batch_id;        // Assigned by Sequence in case different
                            // batches is necessary
                            // Can be sent to scoreboard to generate
                            // expected data

  int index;                // used to indicate serial number of this
                            // transaction, DON'T use rand for better
                            // control

  bit last;                 // Final-work marker, 1: Indicate last transaction

  virtual function void do_copy(uvm_object rhs);
    packet_base_trans_c rhs_copied;
    if (!$cast(rhs_copied, rhs))
      `uvm_fatal("PKT_BASE", "Can't Cast downstream")

    // Initialize index
    this.index = 0;
  endfunction

  // Register fields for automatic record/print/compare
  `uvm_object_utils_begin(packet_base_trans_c)
    `uvm_field_int(packet_length, UVM_ALL_ON)
    `uvm_field_int(batch_id,      UVM_ALL_ON) // Indicate ID for each batch
    `uvm_field_int(index,         UVM_ALL_ON) // Calculated index
    `uvm_field_int(last,          UVM_ALL_ON) // last transaction
  `uvm_object_utils_end

endclass
