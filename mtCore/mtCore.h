//
//  mtCore.hpp
//  mt
//
//  Created by Mano Rajesh on 12/9/25.
//

#pragma once
#include <dispatch/dispatch.h>
#include <functional>

class mtCore {
public:
  mtCore();
  ~mtCore();

  bool start(); // create PTY + spawn shell
  void send(const char *data, size_t len);

  std::function<void(const char *, size_t)> onOutput;

private:
  int master_fd = -1;
  dispatch_source_t ptySource = nullptr;
};
